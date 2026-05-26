# Schema definition: 22 gen-schema kinds modeling multi-datacenter infrastructure.
#
# Uses lib.evalModules with mkSchemaOption for kind declarations and
# mkInstanceRegistry for fleet instance registries. Refs are resolved
# via deferred ref bindings (string keys → instance lookups).
{ lib, schemaLib }:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    mkFieldValidator
    ref
    setOf
    ;

  # Refinement contracts
  refinements = {
    cidr = [{
      check = v: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+" v != null;
      message = "must be valid CIDR notation (e.g., 10.0.0.0/16)";
    }];
    ipv4Address = [{
      check = v: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" v != null;
      message = "must be a valid IPv4 address";
    }];
    macAddress = [{
      check = v: builtins.match "[0-9a-fA-F][0-9a-fA-F](:[0-9a-fA-F][0-9a-fA-F]){5}" v != null;
      message = "must be a valid MAC address (e.g., 00:11:22:33:44:55)";
    }];
    vlanId = [{
      check = v: v >= 1 && v <= 4094;
      message = "VLAN ID must be 1-4094";
    }];
    envTier = [{
      check = v: builtins.elem v [ "dev" "staging" "prod" ];
      message = "must be dev, staging, or prod";
    }];
    serviceProtocol = [{
      check = v: builtins.elem v [ "tcp" "udp" "http" "grpc" ];
      message = "must be tcp, udp, http, or grpc";
    }];
    dnsRecordType = [{
      check = v: builtins.elem v [ "A" "AAAA" "CNAME" "MX" "TXT" ];
      message = "must be A, AAAA, CNAME, MX, or TXT";
    }];
    lbAlgorithm = [{
      check = v: builtins.elem v [ "roundrobin" "leastconn" "iphash" ];
      message = "must be roundrobin, leastconn, or iphash";
    }];
    firewallAction = [{
      check = v: builtins.elem v [ "allow" "deny" ];
      message = "must be allow or deny";
    }];
    certIssuer = [{
      check = v: builtins.elem v [ "letsencrypt" "internal-ca" "acme" ];
      message = "must be letsencrypt, internal-ca, or acme";
    }];
    tcpPort = [{
      check = v: v >= 1 && v <= 65535;
      message = "must be a valid TCP port (1-65535)";
    }];
    positive = [{
      check = v: v > 0;
      message = "must be positive";
    }];
    nonEmpty = [{
      check = v: v != "";
      message = "must not be empty";
    }];
  };

  # Row-polymorphic validators
  validators = {
    server-ram-proportional = mkFieldValidator {
      name = "server-ram-proportional";
      fields = [ "cores" "ram_gb" ];
      check = s: s.ram_gb >= s.cores * 2;
      message = "server RAM must be at least 2x cores";
    };
    dns-record-has-target = mkFieldValidator {
      name = "dns-record-has-target";
      fields = [ "server" "loadbalancer" ];
      check = r: r.server != null || r.loadbalancer != null;
      message = "DNS record must reference a server or loadbalancer";
    };
    cert-has-target = mkFieldValidator {
      name = "cert-has-target";
      fields = [ "server" "loadbalancer" ];
      check = c: c.server != null || c.loadbalancer != null;
      message = "certificate must be bound to a server or loadbalancer";
    };
    no-self-dependency = mkFieldValidator {
      name = "no-self-dependency";
      fields = [ "upstream" "downstream" ];
      check = d: d.upstream != d.downstream;
      message = "service cannot depend on itself";
    };
  };

  # Build the fully evaluated schema + fleet system.
  # fleet: raw attrset of kind → { instanceName → instanceData }
  evalSchema = fleet:
    let
      eval = lib.evalModules {
        modules = [
          {
            # ── Schema kind declarations ──
            options.schema = mkSchemaOption { };

            # Infrastructure topology
            config.schema.datacenter = {
              options.region = lib.mkOption { type = lib.types.str; };
            };

            config.schema.environment = {
              options.tier = lib.mkOption { type = lib.types.str; };
            };

            config.schema.network = {
              parent = "datacenter";
              options.cidr = lib.mkOption { type = lib.types.str; };
              options.datacenter = lib.mkOption { type = ref "datacenter"; };
            };

            config.schema.subnet = {
              parent = "network";
              options.cidr = lib.mkOption { type = lib.types.str; };
              options.gateway = lib.mkOption { type = lib.types.str; };
              options.network = lib.mkOption { type = ref "network"; };
            };

            config.schema.vlan = {
              parent = "subnet";
              options.id = lib.mkOption { type = lib.types.int; };
              options.vlan-name = lib.mkOption { type = lib.types.str; };
              options.subnet = lib.mkOption { type = ref "subnet"; };
            };

            # Compute
            config.schema.server = {
              options.hostname = lib.mkOption { type = lib.types.str; };
              options.os = lib.mkOption { type = lib.types.str; };
              options.cores = lib.mkOption { type = lib.types.int; };
              options.ram_gb = lib.mkOption { type = lib.types.int; };
              options.tags = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
              options.datacenter = lib.mkOption { type = ref "datacenter"; };
              options.environment = lib.mkOption { type = ref "environment"; };
              options.subnet = lib.mkOption { type = ref "subnet"; };
              options.replaces = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
              validators = [ validators.server-ram-proportional ];
            };

            config.schema.interface = {
              parent = "server";
              options.mac = lib.mkOption { type = lib.types.str; };
              options.ip = lib.mkOption { type = lib.types.str; };
              options.primary_ = lib.mkOption { type = lib.types.bool; };
              options.server = lib.mkOption { type = ref "server"; };
              options.vlan = lib.mkOption { type = ref "vlan"; };
            };

            # Services
            config.schema.service = {
              options.protocol = lib.mkOption { type = lib.types.str; };
              options.healthcheck = lib.mkOption { type = lib.types.str; };
              options.server = lib.mkOption { type = ref "server"; };
              options.environment = lib.mkOption { type = ref "environment"; };
            };

            config.schema.port = {
              parent = "service";
              options.number = lib.mkOption { type = lib.types.int; };
              options.protocol = lib.mkOption { type = lib.types.str; };
              options.expose = lib.mkOption { type = lib.types.bool; };
              options.service = lib.mkOption { type = ref "service"; };
            };

            config.schema.service-dependency = {
              options.upstream = lib.mkOption { type = ref "service"; };
              options.downstream = lib.mkOption { type = ref "service"; };
              options.required = lib.mkOption { type = lib.types.bool; };
              options.protocol = lib.mkOption { type = lib.types.str; };
              validators = [ validators.no-self-dependency ];
            };

            # DNS
            config.schema.domain = {
              options.tld = lib.mkOption { type = lib.types.bool; };
              options.wildcard = lib.mkOption { type = lib.types.bool; };
              options.environment = lib.mkOption { type = ref "environment"; };
            };

            config.schema.dns-record = {
              parent = "domain";
              options.type = lib.mkOption { type = lib.types.str; };
              options.ttl = lib.mkOption { type = lib.types.int; };
              options.server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
              options.loadbalancer = lib.mkOption { type = lib.types.nullOr (ref "loadbalancer"); default = null; };
              options.domain = lib.mkOption { type = ref "domain"; };
              validators = [ validators.dns-record-has-target ];
            };

            # Load balancing
            config.schema.loadbalancer = {
              options.algorithm = lib.mkOption { type = lib.types.str; };
              options.datacenter = lib.mkOption { type = ref "datacenter"; };
              options.environment = lib.mkOption { type = ref "environment"; };
              options.failover = lib.mkOption { type = lib.types.nullOr (ref "loadbalancer"); default = null; };
            };

            config.schema.backend = {
              parent = "loadbalancer";
              options.weight = lib.mkOption { type = lib.types.int; };
              options.maxconn = lib.mkOption { type = lib.types.int; };
              options.service = lib.mkOption { type = ref "service"; };
              options.loadbalancer = lib.mkOption { type = ref "loadbalancer"; };
            };

            # Firewall
            config.schema.firewall-rule = {
              options.src-subnet = lib.mkOption { type = ref "subnet"; };
              options.dst-subnet = lib.mkOption { type = ref "subnet"; };
              options.src-server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
              options.dst-server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
              options.protocol = lib.mkOption { type = lib.types.str; };
              options.port = lib.mkOption { type = lib.types.int; };
              options.action = lib.mkOption { type = lib.types.str; };
              options.priority = lib.mkOption { type = lib.types.int; };
            };

            # Certificates
            config.schema.certificate = {
              options.domains = lib.mkOption { type = lib.types.listOf lib.types.str; };
              options.issuer = lib.mkOption { type = lib.types.str; };
              options.expires-days = lib.mkOption { type = lib.types.int; };
              options.server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
              options.loadbalancer = lib.mkOption { type = lib.types.nullOr (ref "loadbalancer"); default = null; };
              validators = [ validators.cert-has-target ];
            };

            # Scheduling
            config.schema.schedule = {
              options.cron = lib.mkOption { type = lib.types.str; };
              options.enabled = lib.mkOption { type = lib.types.bool; };
              options.service = lib.mkOption { type = ref "service"; };
              options.server = lib.mkOption { type = ref "server"; };
            };

            # Identity
            config.schema.ldap-group = {
              options.gid = lib.mkOption { type = lib.types.int; };
              options.description = lib.mkOption { type = lib.types.str; };
            };

            config.schema.ldap-role = {
              options.permissions = lib.mkOption { type = lib.types.listOf lib.types.str; };
              options.ldap-group = lib.mkOption { type = ref "ldap-group"; };
            };

            config.schema.user = {
              options.uid = lib.mkOption { type = lib.types.int; };
              options.shell = lib.mkOption { type = lib.types.str; };
              options.ssh-key = lib.mkOption { type = lib.types.str; };
              options.ldap-role = lib.mkOption { type = ref "ldap-role"; };
              options.servers = lib.mkOption { type = setOf (ref "server"); default = []; };
              options.manager = lib.mkOption { type = lib.types.nullOr (ref "user"); default = null; };
            };

            # Policy
            config.schema.access-policy = {
              options.ldap-role = lib.mkOption { type = ref "ldap-role"; };
              options.resource-kind = lib.mkOption { type = lib.types.str; };
              options.scope = lib.mkOption { type = lib.types.str; };
              options.actions = lib.mkOption { type = lib.types.listOf lib.types.str; };
            };

            # ── Instance registries ──
            options.datacenters = mkInstanceRegistry eval.config.schema "datacenter" { };
            options.environments = mkInstanceRegistry eval.config.schema "environment" {
              refinements.tier = refinements.envTier;
            };
            options.networks = mkInstanceRegistry eval.config.schema "network" {
              refs.datacenter = eval.config.datacenters;
              refinements.cidr = refinements.cidr;
            };
            options.subnets = mkInstanceRegistry eval.config.schema "subnet" {
              refs.network = eval.config.networks;
              refinements.cidr = refinements.cidr;
              refinements.gateway = refinements.ipv4Address;
            };
            options.vlans = mkInstanceRegistry eval.config.schema "vlan" {
              refs.subnet = eval.config.subnets;
              refinements.id = refinements.vlanId;
            };
            options.servers = mkInstanceRegistry eval.config.schema "server" {
              refs.datacenter = eval.config.datacenters;
              refs.environment = eval.config.environments;
              refs.subnet = eval.config.subnets;
              refs.replaces = {
                instances = eval.config.servers;
                deferred = true;
              };
              refinements.hostname = refinements.nonEmpty;
              refinements.cores = refinements.positive;
              refinements.ram_gb = refinements.positive;
            };
            options.interfaces = mkInstanceRegistry eval.config.schema "interface" {
              refs.server = eval.config.servers;
              refs.vlan = eval.config.vlans;
              refinements.mac = refinements.macAddress;
              refinements.ip = refinements.ipv4Address;
            };
            options.services = mkInstanceRegistry eval.config.schema "service" {
              refs.server = eval.config.servers;
              refs.environment = eval.config.environments;
              refinements.protocol = refinements.serviceProtocol;
            };
            options.ports = mkInstanceRegistry eval.config.schema "port" {
              refs.service = eval.config.services;
              refinements.number = refinements.tcpPort;
              refinements.protocol = refinements.serviceProtocol;
            };
            options.service-dependencies = mkInstanceRegistry eval.config.schema "service-dependency" {
              refs.upstream = eval.config.services;
              refs.downstream = eval.config.services;
              refinements.protocol = refinements.serviceProtocol;
            };
            options.domains = mkInstanceRegistry eval.config.schema "domain" {
              refs.environment = eval.config.environments;
            };
            options.dns-records = mkInstanceRegistry eval.config.schema "dns-record" {
              refs.server = eval.config.servers;
              refs.loadbalancer = eval.config.loadbalancers;
              refs.domain = eval.config.domains;
              refinements.type = refinements.dnsRecordType;
              refinements.ttl = refinements.positive;
            };
            options.loadbalancers = mkInstanceRegistry eval.config.schema "loadbalancer" {
              refs.datacenter = eval.config.datacenters;
              refs.environment = eval.config.environments;
              refs.failover = {
                instances = eval.config.loadbalancers;
                deferred = true;
              };
              refinements.algorithm = refinements.lbAlgorithm;
            };
            options.backends = mkInstanceRegistry eval.config.schema "backend" {
              refs.service = eval.config.services;
              refs.loadbalancer = eval.config.loadbalancers;
              refinements.weight = refinements.positive;
              refinements.maxconn = refinements.positive;
            };
            options.firewall-rules = mkInstanceRegistry eval.config.schema "firewall-rule" {
              refs.src-subnet = eval.config.subnets;
              refs.dst-subnet = eval.config.subnets;
              refs.src-server = eval.config.servers;
              refs.dst-server = eval.config.servers;
              refinements.protocol = refinements.serviceProtocol;
              refinements.port = refinements.tcpPort;
              refinements.action = refinements.firewallAction;
              refinements.priority = refinements.positive;
            };
            options.certificates = mkInstanceRegistry eval.config.schema "certificate" {
              refs.server = eval.config.servers;
              refs.loadbalancer = eval.config.loadbalancers;
              refinements.issuer = refinements.certIssuer;
              refinements.expires-days = refinements.positive;
            };
            options.schedules = mkInstanceRegistry eval.config.schema "schedule" {
              refs.service = eval.config.services;
              refs.server = eval.config.servers;
            };
            options.ldap-groups = mkInstanceRegistry eval.config.schema "ldap-group" { };
            options.ldap-roles = mkInstanceRegistry eval.config.schema "ldap-role" {
              refs.ldap-group = eval.config.ldap-groups;
            };
            options.users = mkInstanceRegistry eval.config.schema "user" {
              refs.ldap-role = eval.config.ldap-roles;
              refs.servers = eval.config.servers;
              refs.manager = {
                instances = eval.config.users;
                deferred = true;
              };
            };
            options.access-policies = mkInstanceRegistry eval.config.schema "access-policy" {
              refs.ldap-role = eval.config.ldap-roles;
            };

            # ── Fleet data (config values) ──
            config.datacenters = fleet.datacenter or {};
            config.environments = fleet.environment or {};
            config.networks = fleet.network or {};
            config.subnets = fleet.subnet or {};
            config.vlans = lib.mapAttrs (_: v: builtins.removeAttrs v [ "name" ] // { vlan-name = v.name; }) (fleet.vlan or {});
            config.servers = fleet.server or {};
            config.interfaces = fleet.interface or {};
            config.services = fleet.service or {};
            config.ports = fleet.port or {};
            config.service-dependencies = fleet.service-dependency or {};
            config.domains = fleet.domain or {};
            config.dns-records = fleet.dns-record or {};
            config.loadbalancers = fleet.loadbalancer or {};
            config.backends = fleet.backend or {};
            config.firewall-rules = fleet.firewall-rule or {};
            config.certificates = fleet.certificate or {};
            config.schedules = fleet.schedule or {};
            config.ldap-groups = fleet.ldap-group or {};
            config.ldap-roles = fleet.ldap-role or {};
            config.users = fleet.user or {};
            config.access-policies = fleet.access-policy or {};
          }
        ];
      };
    in
    {
      inherit (eval.config) schema;
      # Expose evaluated fleet registries
      fleet = {
        datacenter = eval.config.datacenters;
        environment = eval.config.environments;
        network = eval.config.networks;
        subnet = eval.config.subnets;
        vlan = eval.config.vlans;
        server = eval.config.servers;
        interface = eval.config.interfaces;
        service = eval.config.services;
        port = eval.config.ports;
        service-dependency = eval.config.service-dependencies;
        domain = eval.config.domains;
        dns-record = eval.config.dns-records;
        loadbalancer = eval.config.loadbalancers;
        backend = eval.config.backends;
        firewall-rule = eval.config.firewall-rules;
        certificate = eval.config.certificates;
        schedule = eval.config.schedules;
        ldap-group = eval.config.ldap-groups;
        ldap-role = eval.config.ldap-roles;
        user = eval.config.users;
        access-policy = eval.config.access-policies;
      };
      inherit refinements validators;
    };
in
{
  inherit evalSchema refinements validators;
}
