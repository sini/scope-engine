# Demo fleet data — multi-datacenter infrastructure
# Flat registries keyed by kind name, instances keyed by name.
{
  datacenter = {
    us-east-1 = { region = "us-east"; };
    eu-west-1 = { region = "eu-west"; };
  };

  environment = {
    prod = { tier = "prod"; };
    staging = { tier = "staging"; };
  };

  network = {
    "us-east-1.primary" = { cidr = "10.0.0.0/16"; datacenter = "us-east-1"; };
    "eu-west-1.primary" = { cidr = "172.16.0.0/16"; datacenter = "eu-west-1"; };
  };

  subnet = {
    "us-east-1.primary.web" = { cidr = "10.0.1.0/24"; gateway = "10.0.1.1"; network = "us-east-1.primary"; };
    "us-east-1.primary.db" = { cidr = "10.0.2.0/24"; gateway = "10.0.2.1"; network = "us-east-1.primary"; };
    "eu-west-1.primary.app" = { cidr = "172.16.1.0/24"; gateway = "172.16.1.1"; network = "eu-west-1.primary"; };
  };

  vlan = {
    "us-east-1.primary.web.100" = { id = 100; name = "web-vlan"; subnet = "us-east-1.primary.web"; };
    "us-east-1.primary.db.200" = { id = 200; name = "db-vlan"; subnet = "us-east-1.primary.db"; };
  };

  server = {
    web-1 = {
      hostname = "web-1"; os = "nixos"; cores = 4; ram_gb = 8;
      datacenter = "us-east-1"; environment = "prod"; subnet = "us-east-1.primary.web";
      tags = [ "web" "frontend" ];
    };
    web-2 = {
      hostname = "web-2"; os = "nixos"; cores = 4; ram_gb = 8;
      datacenter = "us-east-1"; environment = "prod"; subnet = "us-east-1.primary.web";
      tags = [ "web" "frontend" ]; replaces = "web-1";
    };
    db-1 = {
      hostname = "db-1"; os = "nixos"; cores = 8; ram_gb = 32;
      datacenter = "us-east-1"; environment = "prod"; subnet = "us-east-1.primary.db";
      tags = [ "database" ];
    };
    api-1 = {
      hostname = "api-1"; os = "nixos"; cores = 4; ram_gb = 16;
      datacenter = "eu-west-1"; environment = "prod"; subnet = "eu-west-1.primary.app";
      tags = [ "api" ];
    };
  };

  interface = {
    "web-1.eth0" = { mac = "00:11:22:33:44:01"; ip = "10.0.1.10"; primary_ = true; server = "web-1"; vlan = "us-east-1.primary.web.100"; };
    "web-2.eth0" = { mac = "00:11:22:33:44:03"; ip = "10.0.1.11"; primary_ = true; server = "web-2"; vlan = "us-east-1.primary.web.100"; };
    "db-1.eth0" = { mac = "00:11:22:33:44:02"; ip = "10.0.2.10"; primary_ = true; server = "db-1"; vlan = "us-east-1.primary.db.200"; };
  };

  service = {
    nginx = { protocol = "http"; healthcheck = "/health"; server = "web-1"; environment = "prod"; };
    postgres = { protocol = "tcp"; healthcheck = "/ready"; server = "db-1"; environment = "prod"; };
    api = { protocol = "grpc"; healthcheck = "/grpc.health.v1.Health/Check"; server = "api-1"; environment = "prod"; };
  };

  port = {
    "nginx.http" = { number = 80; protocol = "tcp"; expose = true; service = "nginx"; };
    "nginx.https" = { number = 443; protocol = "tcp"; expose = true; service = "nginx"; };
    "postgres.pg" = { number = 5432; protocol = "tcp"; expose = false; service = "postgres"; };
    "api.grpc" = { number = 50051; protocol = "tcp"; expose = true; service = "api"; };
  };

  domain = {
    "example.com" = { tld = true; wildcard = false; environment = "prod"; };
    "api.example.com" = { tld = false; wildcard = false; environment = "prod"; };
  };

  dns-record = {
    "example.com.web" = { type = "A"; ttl = 300; server = "web-1"; loadbalancer = null; domain = "example.com"; };
    "api.example.com.api" = { type = "A"; ttl = 60; server = null; loadbalancer = "lb-prod-east"; domain = "api.example.com"; };
  };

  loadbalancer = {
    lb-prod-east = { algorithm = "roundrobin"; datacenter = "us-east-1"; environment = "prod"; };
    lb-prod-east-standby = { algorithm = "roundrobin"; datacenter = "us-east-1"; environment = "prod"; failover = "lb-prod-east"; };
  };

  backend = {
    "lb-prod-east.nginx-1" = { weight = 50; maxconn = 1000; service = "nginx"; loadbalancer = "lb-prod-east"; };
    "lb-prod-east.nginx-2" = { weight = 50; maxconn = 1000; service = "nginx"; loadbalancer = "lb-prod-east"; };
  };

  service-dependency = {
    api-needs-postgres = { upstream = "postgres"; downstream = "api"; required = true; protocol = "tcp"; };
    nginx-proxies-api = { upstream = "api"; downstream = "nginx"; required = false; protocol = "grpc"; };
  };

  firewall-rule = {
    web-to-db = {
      src-subnet = "us-east-1.primary.web"; dst-subnet = "us-east-1.primary.db";
      protocol = "tcp"; port = 5432; action = "allow"; priority = 100;
    };
    web-to-web-health = {
      src-subnet = "us-east-1.primary.web"; dst-subnet = "us-east-1.primary.web";
      protocol = "tcp"; port = 8080; action = "allow"; priority = 200;
    };
    deny-db-outbound = {
      src-subnet = "us-east-1.primary.db"; dst-subnet = "eu-west-1.primary.app";
      protocol = "tcp"; port = 443; action = "deny"; priority = 50;
    };
  };

  certificate = {
    wildcard-example = {
      domains = [ "*.example.com" "example.com" ];
      issuer = "letsencrypt"; expires-days = 90;
      server = null; loadbalancer = "lb-prod-east";
    };
    api-internal = {
      domains = [ "api.internal" ];
      issuer = "internal-ca"; expires-days = 365;
      server = "api-1"; loadbalancer = null;
    };
  };

  schedule = {
    db-backup = { cron = "0 2 * * *"; service = "postgres"; server = "db-1"; enabled = true; };
    log-rotate = { cron = "0 0 * * 0"; service = "nginx"; server = "web-1"; enabled = true; };
  };

  ldap-group = {
    engineering = { gid = 1000; description = "Engineering team"; };
    ops = { gid = 1001; description = "Operations team"; };
  };

  ldap-role = {
    admin = { permissions = [ "sudo" "deploy" "restart" ]; ldap-group = "ops"; };
    developer = { permissions = [ "deploy" "logs" ]; ldap-group = "engineering"; };
  };

  user = {
    alice = {
      uid = 1000; shell = "/bin/zsh"; ssh-key = "ssh-ed25519 AAAA...";
      ldap-role = "admin"; servers = [ "web-1" "db-1" ];
    };
    bob = {
      uid = 1001; shell = "/bin/bash"; ssh-key = "ssh-ed25519 BBBB...";
      ldap-role = "developer"; servers = [ "api-1" ]; manager = "alice";
    };
  };

  access-policy = {
    ops-server-sudo = {
      ldap-role = "admin"; resource-kind = "server";
      scope = "direct"; actions = [ "sudo" "restart" "ssh" ];
    };
    ops-lb-manage = {
      ldap-role = "admin"; resource-kind = "loadbalancer";
      scope = "transitive"; actions = [ "drain" "reload" ];
    };
    eng-service-deploy = {
      ldap-role = "developer"; resource-kind = "service";
      scope = "transitive"; actions = [ "deploy" "logs" "rollback" ];
    };
    eng-server-logs = {
      ldap-role = "developer"; resource-kind = "server";
      scope = "direct"; actions = [ "logs" "ssh" ];
    };
  };
}
