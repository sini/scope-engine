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

  graph = {
    test-kind-node-count = {
      expr = graphLib.sizeNodes sql.kindNodes;
      expected = 21;
    };

    test-kind-roots = {
      # Roots: kinds with no incoming import edges
      expr = sql.kindRoots;
      expected = graphLib.roots sql.kindNodes;
    };

    test-kind-self-ref-cycles = {
      # Self-referential kinds (server.replaces, user.manager, lb.failover)
      # create kind-level cycles; instance-level graph is acyclic
      expr = builtins.sort builtins.lessThan sql.kindCycles;
      expected = [ "loadbalancer" "server" "user" ];
    };

    test-instance-node-count = {
      # Total instances across all kinds
      expr = graphLib.sizeNodes sql.instanceNodes;
      expected =
        let
          counts = lib.mapAttrsToList (_: instances: builtins.length (builtins.attrNames instances)) fleet;
        in
        lib.foldl' builtins.add 0 counts;
    };

    test-instance-no-cycles = {
      expr = graphLib.cycles sql.instanceNodes;
      expected = [];
    };

    test-reachable-from-server = {
      # From web-1, can reach datacenter, environment, subnet via import edges
      expr =
        let
          reachable = sql.reachableFrom "server:web-1";
        in
        builtins.elem "datacenter:us-east-1" reachable
        && builtins.elem "environment:prod" reachable
        && builtins.elem "subnet:us-east-1.primary.web" reachable;
      expected = true;
    };

    test-dependents-of-datacenter = {
      # Dependents: things that import us-east-1
      expr =
        let
          deps = sql.dependents "datacenter:us-east-1";
        in
        builtins.elem "server:web-1" deps
        && builtins.elem "network:us-east-1.primary" deps;
      expected = true;
    };

    test-select-servers = {
      expr =
        let
          serverNodes = graphLib.select sql.instanceNodes (n: n.type == "server");
        in
        builtins.sort builtins.lessThan (builtins.attrNames serverNodes);
      expected = [ "server:api-1" "server:db-1" "server:web-1" "server:web-2" ];
    };

    test-service-dependency-chain = {
      # nginx → api → postgres via service-dependency import edges
      expr =
        let
          reachable = sql.reachableFrom "service-dependency:nginx-proxies-api";
        in
        builtins.elem "service:api" reachable && builtins.elem "service:nginx" reachable;
      expected = true;
    };
  };

  sql-parser =
    let
      inherit (sql) parseSql;
    in
    {
      test-simple-select = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers";
          in {
            cols = ast.select;
            kind = ast.from.kind;
          };
        expected = {
          cols = [ { column = "hostname"; table = null; } ];
          kind = "servers";
        };
      };

      test-select-star = {
        expr =
          let ast = parseSql "SELECT * FROM servers";
          in ast.select;
        expected = [ { column = "*"; table = null; } ];
      };

      test-select-with-alias = {
        expr =
          let ast = parseSql "SELECT s.hostname, s.os FROM servers s";
          in {
            cols = ast.select;
            alias = ast.from.alias;
          };
        expected = {
          cols = [
            { table = "s"; column = "hostname"; }
            { table = "s"; column = "os"; }
          ];
          alias = "s";
        };
      };

      test-single-join = {
        expr =
          let ast = parseSql "SELECT s.hostname FROM servers s JOIN services svc ON svc.server = s.name";
          in builtins.length ast.joins;
        expected = 1;
      };

      test-join-details = {
        expr =
          let ast = parseSql "SELECT s.hostname FROM servers s JOIN services svc ON svc.server = s.name";
              j = builtins.head ast.joins;
          in {
            kind = j.kind;
            alias = j.alias;
            isLeft = j.isLeft;
            onLeft = j.on.left;
            onRight = j.on.right;
          };
        expected = {
          kind = "services";
          alias = "svc";
          isLeft = false;
          onLeft = { table = "svc"; column = "server"; };
          onRight = { table = "s"; column = "name"; };
        };
      };

      test-multi-join = {
        expr =
          let ast = parseSql ''
            SELECT s.hostname, svc.name, p.number
            FROM servers s
            JOIN services svc ON svc.server = s.name
            JOIN ports p ON p.service = svc.name
          '';
          in builtins.length ast.joins;
        expected = 2;
      };

      test-where-eq = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers WHERE datacenter = 'us-east-1'";
          in ast.where;
        expected = {
          op = "=";
          left = { table = null; column = "datacenter"; };
          right = "us-east-1";
        };
      };

      test-where-and = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers WHERE datacenter = 'us-east-1' AND environment = 'prod'";
          in ast.where.op;
        expected = "AND";
      };

      test-where-in = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers WHERE datacenter IN ('us-east-1', 'eu-west-1')";
          in ast.where;
        expected = {
          op = "IN";
          left = { table = null; column = "datacenter"; };
          right = [ "us-east-1" "eu-west-1" ];
        };
      };

      test-where-is-null = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers WHERE replaces IS NULL";
          in ast.where;
        expected = {
          op = "IS NULL";
          left = { table = null; column = "replaces"; };
        };
      };

      test-where-is-not-null = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers WHERE replaces IS NOT NULL";
          in ast.where;
        expected = {
          op = "IS NOT NULL";
          left = { table = null; column = "replaces"; };
        };
      };

      test-order-by = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers ORDER BY hostname";
          in ast.orderBy;
        expected = { table = null; column = "hostname"; };
      };

      test-limit = {
        expr =
          let ast = parseSql "SELECT hostname FROM servers LIMIT 10";
          in ast.limit;
        expected = 10;
      };

      test-left-join = {
        expr =
          let ast = parseSql "SELECT s.hostname FROM servers s LEFT JOIN services svc ON svc.server = s.name";
              j = builtins.head ast.joins;
          in j.isLeft;
        expected = true;
      };

      test-full-query = {
        expr =
          let ast = parseSql ''
            SELECT s.hostname, s.cores
            FROM servers s
            JOIN services svc ON svc.server = s.name
            WHERE s.datacenter = 'us-east-1'
            ORDER BY s.hostname
            LIMIT 5
          '';
          in {
            selectCount = builtins.length ast.select;
            joinCount = builtins.length ast.joins;
            hasWhere = ast.where != null;
            hasOrderBy = ast.orderBy != null;
            limit = ast.limit;
          };
        expected = {
          selectCount = 2;
          joinCount = 1;
          hasWhere = true;
          hasOrderBy = true;
          limit = 5;
        };
      };
    };

  sql-engine =
    let
      inherit (sql) query;
    in
    {
      test-simple-select = {
        expr =
          let
            rows = query "SELECT hostname, os FROM servers";
          in
          builtins.length rows;
        expected = 4;
      };

      test-select-star = {
        expr =
          let
            rows = query "SELECT * FROM servers";
            r = builtins.head rows;
          in
          r ? hostname && r ? os && r ? cores;
        expected = true;
      };

      test-where-filter = {
        expr =
          let
            rows = query "SELECT hostname FROM servers WHERE datacenter = 'us-east-1'";
          in
          builtins.sort builtins.lessThan (map (r: r.hostname) rows);
        expected = [ "db-1" "web-1" "web-2" ];
      };

      test-where-inequality = {
        expr =
          let
            rows = query "SELECT hostname FROM servers WHERE datacenter != 'us-east-1'";
          in
          map (r: r.hostname) rows;
        expected = [ "api-1" ];
      };

      test-single-join = {
        expr =
          let
            rows = query ''
              SELECT s.hostname, svc.name
              FROM servers s
              JOIN services svc ON svc.server = s.name
            '';
          in
          builtins.sort builtins.lessThan (map (r: r.name) rows);
        expected = [ "api" "nginx" "postgres" ];
      };

      test-where-with-join = {
        expr =
          let
            rows = query ''
              SELECT s.hostname, svc.name
              FROM servers s
              JOIN services svc ON svc.server = s.name
              WHERE s.datacenter = 'us-east-1'
            '';
          in
          builtins.sort builtins.lessThan (map (r: r.name) rows);
        expected = [ "nginx" "postgres" ];
      };

      test-order-by = {
        expr =
          let
            rows = query "SELECT hostname FROM servers ORDER BY hostname";
          in
          map (r: r.hostname) rows;
        expected = [ "api-1" "db-1" "web-1" "web-2" ];
      };

      test-limit = {
        expr =
          let
            rows = query "SELECT hostname FROM servers ORDER BY hostname LIMIT 2";
          in
          map (r: r.hostname) rows;
        expected = [ "api-1" "db-1" ];
      };

      test-where-is-null = {
        expr =
          let
            rows = query "SELECT hostname FROM servers WHERE replaces IS NULL";
          in
          builtins.length rows;
        # web-1, db-1, api-1 have no replaces; web-2 has replaces = "web-1"
        expected = 3;
      };

      test-where-is-not-null = {
        expr =
          let
            rows = query "SELECT hostname FROM servers WHERE replaces IS NOT NULL";
          in
          map (r: r.hostname) rows;
        expected = [ "web-2" ];
      };

      test-multi-join = {
        expr =
          let
            rows = query ''
              SELECT s.hostname, svc.name, p.number
              FROM servers s
              JOIN services svc ON svc.server = s.name
              JOIN ports p ON p.service = svc.name
              WHERE p.expose = true
            '';
          in
          builtins.length rows > 0;
        expected = true;
      };
    };

  ddl =
    let
      inherit (sql) ddl migrationOrder;
    in
    {
      test-table-count = {
        # At least one CREATE TABLE per schema kind
        expr = builtins.length ddl.tables >= 21;
        expected = true;
      };

      test-migration-order-roots-first = {
        # datacenter, environment, ldap-group have no deps — should come first
        expr =
          let
            firstFew = lib.take 5 migrationOrder;
          in
          builtins.elem "datacenter" firstFew
          && builtins.elem "environment" firstFew
          && builtins.elem "ldap-group" firstFew;
        expected = true;
      };

      test-migration-order-deps-before-dependents = {
        # network depends on datacenter: datacenter must come before network
        expr =
          let
            dcIdx = lib.lists.findFirstIndex (x: x == "datacenter") null migrationOrder;
            netIdx = lib.lists.findFirstIndex (x: x == "network") null migrationOrder;
          in
          dcIdx != null && netIdx != null && dcIdx < netIdx;
        expected = true;
      };

      test-migration-order-all-kinds = {
        expr = builtins.length migrationOrder;
        expected = 21;
      };

      test-reserved-word-escaping = {
        expr = sql.escapeIdent "user";
        expected = "user_";
      };

      test-hyphen-escaping = {
        expr = sql.escapeIdent "dns-record";
        expected = "dns_record";
      };

      test-junction-table-for-setof = {
        # user.servers is setOf → produces junction table
        expr =
          builtins.any (t: lib.hasInfix "user__servers" t || lib.hasInfix "user_servers" t) ddl.tables;
        expected = true;
      };

      test-indexes-generated = {
        expr = builtins.length ddl.indexes > 0;
        expected = true;
      };

      test-views-generated = {
        expr = builtins.length ddl.views;
        expected = 2;
      };

      test-datacenter-table-ddl = {
        # Datacenter table should have name_ and region columns
        expr =
          let
            dcTables = builtins.filter (t: lib.hasInfix "CREATE TABLE datacenter" t) ddl.tables;
          in
          builtins.length dcTables == 1
          && lib.hasInfix "name_ text PRIMARY KEY" (builtins.head dcTables)
          && lib.hasInfix "region text" (builtins.head dcTables);
        expected = true;
      };
    };

  acl =
    let
      inherit (sql) effectiveAccess;
    in
    {
      test-alice-has-server-access = {
        # alice has admin role → ops-server-sudo policy → sudo on assigned servers
        expr = effectiveAccess ? "alice:server:web-1";
        expected = true;
      };

      test-alice-server-actions = {
        expr = effectiveAccess."alice:server:web-1".actions;
        expected = [ "sudo" "restart" "ssh" ];
      };

      test-alice-has-db-access = {
        # alice is assigned to db-1
        expr = effectiveAccess ? "alice:server:db-1";
        expected = true;
      };

      test-bob-has-server-access = {
        # bob has developer role → eng-server-logs policy → logs on assigned servers
        expr = effectiveAccess ? "bob:server:api-1";
        expected = true;
      };

      test-bob-server-actions = {
        expr = effectiveAccess."bob:server:api-1".actions;
        expected = [ "logs" "ssh" ];
      };

      test-alice-service-transitive = {
        # alice has admin role → ops-lb-manage (transitive, loadbalancer)
        # alice is on web-1, nginx runs on web-1, lb-prod-east backends include nginx
        expr = effectiveAccess ? "alice:loadbalancer:lb-prod-east";
        expected = true;
      };

      test-bob-service-transitive = {
        # bob has developer role → eng-service-deploy (transitive, service)
        # bob is on api-1, api service runs on api-1
        expr = effectiveAccess ? "bob:service:api";
        expected = true;
      };

      test-who-has-sudo = {
        # Filter effective access for sudo actions
        expr =
          let
            sudoEntries = lib.filterAttrs (_: ea:
              builtins.elem "sudo" ea.actions
            ) effectiveAccess;
          in
          builtins.sort builtins.lessThan (lib.unique (lib.mapAttrsToList (_: ea: ea.user) sudoEntries));
        expected = [ "alice" ];
      };
    };

  reachability =
    let
      inherit (sql) networkReachability;
    in
    {
      test-web-to-db-allowed = {
        # web-to-db firewall rule allows port 5432 from web subnet to db subnet
        expr =
          let
            key = "web-1:db-1";
          in
          networkReachability ? ${key} && builtins.elem 5432 networkReachability.${key}.allowedPorts;
        expected = true;
      };

      test-web-to-web-self-subnet = {
        # web-to-web-health allows port 8080 within web subnet
        expr =
          let
            key = "web-1:web-2";
          in
          networkReachability ? ${key} && builtins.elem 8080 networkReachability.${key}.allowedPorts;
        expected = true;
      };

      test-db-to-api-denied = {
        # deny-db-outbound blocks db→api, but deny rules don't create reachability
        # There's no allow rule from db subnet to app subnet
        expr = !(networkReachability ? "db-1:api-1");
        expected = true;
      };

      test-reachability-has-path = {
        expr =
          let
            key = "web-1:db-1";
          in
          networkReachability.${key}.path;
        expected = [ "web-1" "db-1" ];
      };
    };

  nixos =
    let
      configs = sql.nixosConfigs;
    in
    {
      # Basic config generation
      test-web1-hostname = {
        expr = configs.web-1.networking.hostName;
        expected = "web-1";
      };

      test-web1-open-ports = {
        expr = builtins.sort builtins.lessThan configs.web-1.networking.firewall.allowedTCPPorts;
        expected = [ 80 443 ];
      };

      test-db1-no-exposed-ports = {
        # postgres port has expose = false
        expr = configs.db-1.networking.firewall.allowedTCPPorts;
        expected = [];
      };

      test-web2-no-services = {
        # web-2 has no services assigned
        expr = configs.web-2.networking.firewall.allowedTCPPorts;
        expected = [];
      };

      test-api1-grpc-port = {
        expr = configs.api-1.networking.firewall.allowedTCPPorts;
        expected = [ 50051 ];
      };

      # User provisioning from LDAP
      test-web1-has-alice = {
        expr = configs.web-1.users.users ? alice;
        expected = true;
      };

      test-web1-alice-has-wheel = {
        # alice has admin role with sudo permission
        expr = builtins.elem "wheel" configs.web-1.users.users.alice.extraGroups;
        expected = true;
      };

      test-api1-has-bob = {
        expr = configs.api-1.users.users ? bob;
        expected = true;
      };

      test-api1-bob-no-wheel = {
        # bob is developer, no sudo
        expr = builtins.elem "wheel" (configs.api-1.users.users.bob.extraGroups or []);
        expected = false;
      };

      # Post-eval queries
      test-servers-with-port-443 = {
        # only web-1 has nginx with exposed 443
        expr = builtins.attrNames (sql.nixosQueries.serversWithPort configs 443);
        expected = [ "web-1" ];
      };

      test-servers-with-sudo = {
        # alice is on web-1 and db-1 with sudo
        expr = builtins.sort builtins.lessThan (builtins.attrNames (sql.nixosQueries.serversWithSudo configs));
        expected = [ "db-1" "web-1" ];
      };

      test-all-open-ports = {
        expr = sql.nixosQueries.allOpenPorts configs;
        expected = {
          web-1 = [ 80 443 ];
          web-2 = [];
          db-1 = [];
          api-1 = [ 50051 ];
        };
      };

      test-servers-in-prod = {
        expr = builtins.sort builtins.lessThan (builtins.attrNames (sql.nixosQueries.serversInEnv configs "prod"));
        expected = [ "api-1" "db-1" "web-1" "web-2" ];
      };

      # Cron jobs from schedules
      test-db1-has-backup-cron = {
        expr = builtins.length configs.db-1.services.cron.systemCronJobs;
        expected = 1;
      };

      test-web1-has-logrotate-cron = {
        expr = builtins.length configs.web-1.services.cron.systemCronJobs;
        expected = 1;
      };
    };

  integration = {
    test-full-pipeline = {
      # Schema → Fleet → Graph → DDL → ACL → Reachability all evaluate
      expr =
        sql.schema != null
        && sql.fleet != null
        && sql.kindNodes != null
        && sql.ddl != null
        && sql.effectiveAccess != null
        && sql.networkReachability != null;
      expected = true;
    };

    test-sql-query-against-fleet = {
      expr =
        let
          rows = sql.query "SELECT hostname FROM servers WHERE datacenter = 'us-east-1' ORDER BY hostname";
        in
        map (r: r.hostname) rows;
      expected = [ "db-1" "web-1" "web-2" ];
    };

    test-ddl-count-matches-kinds = {
      # At least one table per kind, plus junction tables
      expr = builtins.length sql.ddl.tables >= 21;
      expected = true;
    };

    test-migration-order-valid = {
      # Migration order includes all 21 kinds
      expr = builtins.length sql.migrationOrder == 21;
      expected = true;
    };

    test-cross-model-acl-query = {
      # Combine SQL query with ACL synthesis: servers alice has sudo on
      expr =
        let
          sudoEntries = lib.filterAttrs (_: ea:
            builtins.elem "sudo" ea.actions && lib.hasPrefix "server:" ea.resource
          ) sql.effectiveAccess;
          serverNames = map (ea: lib.removePrefix "server:" ea.resource) (builtins.attrValues sudoEntries);
        in
        builtins.sort builtins.lessThan serverNames;
      expected = [ "db-1" "web-1" ];
    };
  };
}
