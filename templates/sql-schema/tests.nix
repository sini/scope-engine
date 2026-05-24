{
  lib,
  engine,
  sql,
  schemaLib,
  graphLib,
  genLib,
}:
let
  inherit (sql) schema fleet;
  meta = schema._meta;
in
{
  smoke = {
    test-fleet-loads = {
      expr = sql.rawFleet != null;
      expected = true;
    };
    test-fleet-has-servers = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames sql.rawFleet.server);
      expected = [ "api-1" "db-1" "web-1" "web-2" ];
    };
  };

  schema = {
    test-kind-count = {
      # 21 schema kinds (effective-access and network-reachability are synthesized, not schema kinds)
      expr = builtins.length meta.kindNames;
      expected = 21;
    };

    test-kind-names = {
      expr = meta.kindNames;
      expected = [
        "access-policy"
        "backend"
        "certificate"
        "datacenter"
        "dns-record"
        "domain"
        "environment"
        "firewall-rule"
        "interface"
        "ldap-group"
        "ldap-role"
        "loadbalancer"
        "network"
        "port"
        "schedule"
        "server"
        "service"
        "service-dependency"
        "subnet"
        "user"
        "vlan"
      ];
    };

    test-network-parent-is-datacenter = {
      expr = meta.topology.network.parent;
      expected = "datacenter";
    };

    test-subnet-parent-is-network = {
      expr = meta.topology.subnet.parent;
      expected = "network";
    };

    test-vlan-parent-is-subnet = {
      expr = meta.topology.vlan.parent;
      expected = "subnet";
    };

    test-interface-parent-is-server = {
      expr = meta.topology.interface.parent;
      expected = "server";
    };

    test-port-parent-is-service = {
      expr = meta.topology.port.parent;
      expected = "service";
    };

    test-backend-parent-is-loadbalancer = {
      expr = meta.topology.backend.parent;
      expected = "loadbalancer";
    };

    test-dns-record-parent-is-domain = {
      expr = meta.topology.dns-record.parent;
      expected = "domain";
    };

    test-roots = {
      # Roots = kinds with no parent in topology (may still have ref edges)
      expr = meta.roots;
      expected = [
        "access-policy"
        "certificate"
        "datacenter"
        "domain"
        "environment"
        "firewall-rule"
        "ldap-group"
        "ldap-role"
        "loadbalancer"
        "schedule"
        "server"
        "service"
        "service-dependency"
        "user"
      ];
    };

    test-server-ref-fields = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (meta.kindMeta "server").refs);
      expected = [ "datacenter" "environment" "replaces" "subnet" ];
    };

    test-user-ref-fields = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (meta.kindMeta "user").refs);
      expected = [ "ldap-role" "manager" "servers" ];
    };
  };

  fleet-eval = {
    test-server-count = {
      expr = builtins.length (builtins.attrNames fleet.server);
      expected = 4;
    };

    test-server-hostname = {
      expr = fleet.server.web-1.hostname;
      expected = "web-1";
    };

    test-server-has-name = {
      expr = fleet.server.web-1.name;
      expected = "web-1";
    };

    test-server-has-nodeid = {
      expr = fleet.server.web-1.nodeId;
      expected = "server:web-1";
    };

    test-server-datacenter-ref-resolves = {
      expr = fleet.server.web-1.datacenter.region;
      expected = "us-east";
    };

    test-server-environment-ref-resolves = {
      expr = fleet.server.web-1.environment.tier;
      expected = "prod";
    };

    test-server-subnet-ref-resolves = {
      expr = fleet.server.web-1.subnet.cidr;
      expected = "10.0.1.0/24";
    };

    test-server-self-ref-resolves = {
      expr = fleet.server.web-2.replaces.hostname;
      expected = "web-1";
    };

    test-server-self-ref-null = {
      expr = fleet.server.web-1.replaces;
      expected = null;
    };

    test-interface-server-ref = {
      expr = fleet.interface."web-1.eth0".server.hostname;
      expected = "web-1";
    };

    test-interface-vlan-ref = {
      expr = fleet.interface."web-1.eth0".vlan.vlan-name;
      expected = "web-vlan";
    };

    test-service-server-ref = {
      expr = fleet.service.nginx.server.hostname;
      expected = "web-1";
    };

    test-dns-record-nullable-server = {
      expr = fleet.dns-record."example.com.web".server.hostname;
      expected = "web-1";
    };

    test-dns-record-nullable-lb = {
      expr = fleet.dns-record."api.example.com.api".loadbalancer.algorithm;
      expected = "roundrobin";
    };

    test-user-servers-setof = {
      expr = builtins.length fleet.user.alice.servers;
      expected = 2;
    };

    test-user-servers-resolved = {
      expr = map (s: s.hostname) fleet.user.alice.servers;
      expected = [ "web-1" "db-1" ];
    };

    test-user-manager-self-ref = {
      expr = fleet.user.bob.manager.uid;
      expected = 1000;
    };

    test-user-manager-null = {
      expr = fleet.user.alice.manager;
      expected = null;
    };

    test-lb-failover-self-ref = {
      expr = fleet.loadbalancer.lb-prod-east-standby.failover.name;
      expected = "lb-prod-east";
    };

    test-service-dependency-refs = {
      expr = fleet.service-dependency.api-needs-postgres.upstream.name;
      expected = "postgres";
    };

    test-backend-service-ref = {
      expr = fleet.backend."lb-prod-east.nginx-1".service.name;
      expected = "nginx";
    };

    test-access-policy-role-ref = {
      expr = fleet.access-policy.ops-server-sudo.ldap-role.name;
      expected = "admin";
    };

    test-certificate-lb-ref = {
      expr = fleet.certificate.wildcard-example.loadbalancer.name;
      expected = "lb-prod-east";
    };

    test-schedule-server-ref = {
      expr = fleet.schedule.db-backup.server.hostname;
      expected = "db-1";
    };
  };

  refinement = {
    test-valid-cidr-passes = {
      expr = fleet.network."us-east-1.primary".cidr;
      expected = "10.0.0.0/16";
    };

    test-invalid-cidr-fails = {
      expr =
        let
          badFleet = sql.rawFleet // { network = { bad = { cidr = "not-cidr"; datacenter = "us-east-1"; }; }; };
          result = builtins.tryEval (builtins.deepSeq (sql.evalSchema badFleet).fleet.network { });
        in
        result.success;
      expected = false;
    };

    test-valid-env-tier = {
      expr = fleet.environment.prod.tier;
      expected = "prod";
    };

    test-invalid-env-tier-fails = {
      expr =
        let
          badFleet = sql.rawFleet // { environment = { bad = { tier = "invalid"; }; }; };
          result = builtins.tryEval (builtins.deepSeq (sql.evalSchema badFleet).fleet.environment { });
        in
        result.success;
      expected = false;
    };

    test-valid-vlan-id = {
      expr = fleet.vlan."us-east-1.primary.web.100".id;
      expected = 100;
    };

    test-valid-mac-address = {
      expr = fleet.interface."web-1.eth0".mac;
      expected = "00:11:22:33:44:01";
    };

    test-valid-tcp-port = {
      expr = fleet.port."nginx.http".number;
      expected = 80;
    };
  };
}
