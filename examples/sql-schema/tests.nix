{
  lib,
  sql,
  schemaLib,
  graphLib,
}:
let
  inherit (sql) schema fleet;
in
{
  smoke = {
    test-fleet-loads = {
      expr = sql.rawFleet != null;
      expected = true;
    };
    test-fleet-has-servers = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames sql.rawFleet.server);
      expected = [
        "api-1"
        "db-1"
        "web-1"
        "web-2"
      ];
    };
  };

  schema = {
    test-kind-count = {
      # 21 schema kinds (effective-access and network-reachability are synthesized, not schema kinds)
      expr = builtins.length schema._kindNames;
      expected = 21;
    };

    test-kind-names = {
      expr = schema._kindNames;
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
      expr = schema._topology.network.parent;
      expected = "datacenter";
    };

    test-subnet-parent-is-network = {
      expr = schema._topology.subnet.parent;
      expected = "network";
    };

    test-vlan-parent-is-subnet = {
      expr = schema._topology.vlan.parent;
      expected = "subnet";
    };

    test-interface-parent-is-server = {
      expr = schema._topology.interface.parent;
      expected = "server";
    };

    test-port-parent-is-service = {
      expr = schema._topology.port.parent;
      expected = "service";
    };

    test-backend-parent-is-loadbalancer = {
      expr = schema._topology.backend.parent;
      expected = "loadbalancer";
    };

    test-dns-record-parent-is-domain = {
      expr = schema._topology.dns-record.parent;
      expected = "domain";
    };

    test-roots = {
      # Roots = kinds with no parent in topology (may still have ref edges)
      expr = schema._roots;
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
      expr = builtins.sort builtins.lessThan (builtins.attrNames schema.server.refs);
      expected = [
        "datacenter"
        "environment"
        "replaces"
        "subnet"
      ];
    };

    test-user-ref-fields = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames schema.user.refs);
      expected = [
        "ldap-role"
        "manager"
        "servers"
      ];
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
      expected = [
        "web-1"
        "db-1"
      ];
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
          badFleet = sql.rawFleet // {
            network = {
              bad = {
                cidr = "not-cidr";
                datacenter = "us-east-1";
              };
            };
          };
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
          badFleet = sql.rawFleet // {
            environment = {
              bad = {
                tier = "invalid";
              };
            };
          };
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
      expr = builtins.length sql.kindNodes.nodes;
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
      expected = [
        "loadbalancer"
        "server"
        "user"
      ];
    };

    test-instance-node-count = {
      # Total instances across all kinds
      expr = builtins.length sql.instanceNodes.nodes;
      expected =
        let
          counts = lib.mapAttrsToList (_: instances: builtins.length (builtins.attrNames instances)) fleet;
        in
        lib.foldl' builtins.add 0 counts;
    };

    test-instance-no-cycles = {
      expr = graphLib.cycles sql.instanceNodes;
      expected = [ ];
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
        builtins.elem "server:web-1" deps && builtins.elem "network:us-east-1.primary" deps;
      expected = true;
    };

    test-select-servers = {
      expr = builtins.sort builtins.lessThan (graphLib.select sql.instanceNodes (n: n.type == "server"));
      expected = [
        "server:api-1"
        "server:db-1"
        "server:web-1"
        "server:web-2"
      ];
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
          let
            ast = parseSql "SELECT hostname FROM servers";
          in
          {
            cols = ast.select;
            kind = ast.from.kind;
          };
        expected = {
          cols = [
            {
              column = "hostname";
              table = null;
            }
          ];
          kind = "servers";
        };
      };

      test-select-star = {
        expr =
          let
            ast = parseSql "SELECT * FROM servers";
          in
          ast.select;
        expected = [
          {
            column = "*";
            table = null;
          }
        ];
      };

      test-select-with-alias = {
        expr =
          let
            ast = parseSql "SELECT s.hostname, s.os FROM servers s";
          in
          {
            cols = ast.select;
            alias = ast.from.alias;
          };
        expected = {
          cols = [
            {
              table = "s";
              column = "hostname";
            }
            {
              table = "s";
              column = "os";
            }
          ];
          alias = "s";
        };
      };

      test-single-join = {
        expr =
          let
            ast = parseSql "SELECT s.hostname FROM servers s JOIN services svc ON svc.server = s.name";
          in
          builtins.length ast.joins;
        expected = 1;
      };

      test-join-details = {
        expr =
          let
            ast = parseSql "SELECT s.hostname FROM servers s JOIN services svc ON svc.server = s.name";
            j = builtins.head ast.joins;
          in
          {
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
          onLeft = {
            table = "svc";
            column = "server";
          };
          onRight = {
            table = "s";
            column = "name";
          };
        };
      };

      test-multi-join = {
        expr =
          let
            ast = parseSql ''
              SELECT s.hostname, svc.name, p.number
              FROM servers s
              JOIN services svc ON svc.server = s.name
              JOIN ports p ON p.service = svc.name
            '';
          in
          builtins.length ast.joins;
        expected = 2;
      };

      test-where-eq = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers WHERE datacenter = 'us-east-1'";
          in
          ast.where;
        expected = {
          op = "=";
          left = {
            table = null;
            column = "datacenter";
          };
          right = "us-east-1";
        };
      };

      test-where-and = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers WHERE datacenter = 'us-east-1' AND environment = 'prod'";
          in
          ast.where.op;
        expected = "AND";
      };

      test-where-in = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers WHERE datacenter IN ('us-east-1', 'eu-west-1')";
          in
          ast.where;
        expected = {
          op = "IN";
          left = {
            table = null;
            column = "datacenter";
          };
          right = [
            "us-east-1"
            "eu-west-1"
          ];
        };
      };

      test-where-is-null = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers WHERE replaces IS NULL";
          in
          ast.where;
        expected = {
          op = "IS NULL";
          left = {
            table = null;
            column = "replaces";
          };
        };
      };

      test-where-is-not-null = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers WHERE replaces IS NOT NULL";
          in
          ast.where;
        expected = {
          op = "IS NOT NULL";
          left = {
            table = null;
            column = "replaces";
          };
        };
      };

      test-order-by = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers ORDER BY hostname";
          in
          ast.orderBy;
        expected = {
          table = null;
          column = "hostname";
        };
      };

      test-limit = {
        expr =
          let
            ast = parseSql "SELECT hostname FROM servers LIMIT 10";
          in
          ast.limit;
        expected = 10;
      };

      test-left-join = {
        expr =
          let
            ast = parseSql "SELECT s.hostname FROM servers s LEFT JOIN services svc ON svc.server = s.name";
            j = builtins.head ast.joins;
          in
          j.isLeft;
        expected = true;
      };

      test-full-query = {
        expr =
          let
            ast = parseSql ''
              SELECT s.hostname, s.cores
              FROM servers s
              JOIN services svc ON svc.server = s.name
              WHERE s.datacenter = 'us-east-1'
              ORDER BY s.hostname
              LIMIT 5
            '';
          in
          {
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
        expected = [
          "db-1"
          "web-1"
          "web-2"
        ];
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
        expected = [
          "api"
          "nginx"
          "postgres"
        ];
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
        expected = [
          "nginx"
          "postgres"
        ];
      };

      test-order-by = {
        expr =
          let
            rows = query "SELECT hostname FROM servers ORDER BY hostname";
          in
          map (r: r.hostname) rows;
        expected = [
          "api-1"
          "db-1"
          "web-1"
          "web-2"
        ];
      };

      test-limit = {
        expr =
          let
            rows = query "SELECT hostname FROM servers ORDER BY hostname LIMIT 2";
          in
          map (r: r.hostname) rows;
        expected = [
          "api-1"
          "db-1"
        ];
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
        expr = builtins.any (t: lib.hasInfix "user__servers" t || lib.hasInfix "user_servers" t) ddl.tables;
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
        expected = [
          "sudo"
          "restart"
          "ssh"
        ];
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
        expected = [
          "logs"
          "ssh"
        ];
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
            sudoEntries = lib.filterAttrs (_: ea: builtins.elem "sudo" ea.actions) effectiveAccess;
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
        expected = [
          "web-1"
          "db-1"
        ];
      };
    };

  bind = {
    test-wrapped-is-true = {
      expr = (sql.buildServerModule sql.rawFleet "web-1").wrapped;
      expected = true;
    };

    test-signature-bound-keys = {
      expr = builtins.sort builtins.lessThan (
        builtins.attrNames (sql.buildServerModule sql.rawFleet "web-1").signature.bound
      );
      expected = [
        "fleet"
        "server"
        "serverName"
      ];
    };

    test-advertised-args-empty = {
      # All args are bound, so no remaining advertised args
      expr = (sql.buildServerModule sql.rawFleet "web-1").advertisedArgs;
      expected = { };
    };

    test-eval-server-module-matches-config = {
      # evalServerModule produces the same config as the old buildServerModule did
      expr = (sql.evalServerModule sql.rawFleet "web-1").networking.hostName;
      expected = "web-1";
    };

    test-contract-violation = {
      expr =
        let
          badFleet = sql.rawFleet // {
            server = {
              bad = {
                os = "nixos";
              };
            };
          };
          result = builtins.tryEval (
            builtins.deepSeq (sql.evalServerModule (sql.evalSchema badFleet).fleet "bad") { }
          );
        in
        result.success;
      expected = false;
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
        expected = [
          80
          443
        ];
      };

      test-db1-no-exposed-ports = {
        # postgres port has expose = false
        expr = configs.db-1.networking.firewall.allowedTCPPorts;
        expected = [ ];
      };

      test-web2-no-services = {
        # web-2 has no services assigned
        expr = configs.web-2.networking.firewall.allowedTCPPorts;
        expected = [ ];
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
        expr = builtins.elem "wheel" (configs.api-1.users.users.bob.extraGroups or [ ]);
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
        expr = builtins.sort builtins.lessThan (
          builtins.attrNames (sql.nixosQueries.serversWithSudo configs)
        );
        expected = [
          "db-1"
          "web-1"
        ];
      };

      test-all-open-ports = {
        expr = sql.nixosQueries.allOpenPorts configs;
        expected = {
          web-1 = [
            80
            443
          ];
          web-2 = [ ];
          db-1 = [ ];
          api-1 = [ 50051 ];
        };
      };

      test-servers-in-prod = {
        expr = builtins.sort builtins.lessThan (
          builtins.attrNames (sql.nixosQueries.serversInEnv configs "prod")
        );
        expected = [
          "api-1"
          "db-1"
          "web-1"
          "web-2"
        ];
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

      # ─── Config-path queries: SELECT WHERE on NixOS config properties ───

      # "Show me all servers where the firewall has port 443 open"
      test-where-firewall-has-443 = {
        expr = builtins.attrNames (
          sql.nixosQueries.serversWhere configs [ "networking" "firewall" "allowedTCPPorts" ] (
            ports: builtins.elem 443 ports
          )
        );
        expected = [ "web-1" ];
      };

      # "Show me all servers where openssh is enabled"
      test-where-ssh-enabled = {
        expr = builtins.sort builtins.lessThan (
          builtins.attrNames (
            sql.nixosQueries.serversWhere configs [ "services" "openssh" "enable" ] (v: v == true)
          )
        );
        expected = [
          "api-1"
          "db-1"
          "web-1"
          "web-2"
        ];
      };

      # "Show me servers that have cron jobs configured"
      test-where-has-cron-jobs = {
        expr = builtins.sort builtins.lessThan (
          builtins.attrNames (
            sql.nixosQueries.serversWhere configs [ "services" "cron" "systemCronJobs" ] (jobs: jobs != [ ])
          )
        );
        expected = [
          "db-1"
          "web-1"
        ];
      };

      # "Show me servers where a specific user exists"
      test-where-user-alice-exists = {
        expr = builtins.sort builtins.lessThan (
          builtins.attrNames (
            sql.nixosQueries.serversWhere configs [ "users" "users" ] (users: users ? alice)
          )
        );
        expected = [
          "db-1"
          "web-1"
        ];
      };

      # "Extract hostnames of servers that have any open ports"
      test-select-hostnames-with-open-ports = {
        expr = sql.nixosQueries.selectFromConfigs configs (cfg: cfg.networking.hostName) (
          hostname:
          let
            cfg = configs.${hostname};
          in
          cfg.networking.firewall.allowedTCPPorts != [ ]
        );
        expected = {
          web-1 = "web-1";
          api-1 = "api-1";
        };
      };

      # "Which servers have the 'database' tag?"
      test-where-tagged-database = {
        expr = builtins.attrNames (
          sql.nixosQueries.serversWhere configs [ "environment" "etc" "server-tags" "text" ] (
            tags: lib.hasInfix "database" tags
          )
        );
        expected = [ "db-1" ];
      };
    };

  # ─── SQL queries against rendered NixOS configs ─────────────────
  # queryHostConfigs flattens host configs into a "hosts" table and
  # evaluates SQL strings against it — querying the BUILT config,
  # not the input fleet data.

  config-queries =
    let
      qhc = sql.queryHostConfigs;
    in
    {
      # "Which hosts have nginx enabled?"
      test-sql-nginx-hosts = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.name) (qhc "SELECT name FROM hosts WHERE nginx_enabled = true")
        );
        expected = [
          "web-1"
          "web-2"
        ]; # both tagged "web"
      };

      # "Which hosts have postgresql enabled?"
      test-sql-postgresql-hosts = {
        expr = map (r: r.name) (qhc "SELECT name FROM hosts WHERE postgresql_enabled = true");
        expected = [ "db-1" ];
      };

      # "Which hosts have sudo enabled?"
      test-sql-sudo-hosts = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.name) (qhc "SELECT name FROM hosts WHERE sudo_enabled = true")
        );
        expected = [
          "db-1"
          "web-1"
        ];
      };

      # "Which hosts have ACME certs?"
      test-sql-acme-hosts = {
        expr = map (r: r.name) (qhc "SELECT name FROM hosts WHERE acme_enabled = true");
        expected = [ "web-1" ];
      };

      # "Show me hostnames and their open TCP ports for hosts with ports open"
      # Use a Nix filter on the SQL result since list-emptiness isn't expressible in our SQL subset
      test-sql-hostname-ports = {
        expr = builtins.sort (a: b: a.hostname < b.hostname) (
          builtins.filter (r: r.open_tcp_ports != [ ]) (qhc "SELECT hostname, open_tcp_ports FROM hosts")
        );
        expected = [
          {
            hostname = "api-1";
            open_tcp_ports = [ 50051 ];
          }
          {
            hostname = "web-1";
            open_tcp_ports = [
              80
              443
            ];
          }
        ];
      };

      # "Which hosts have users but no sudo?"
      test-sql-users-no-sudo = {
        expr = map (r: r.name) (
          qhc "SELECT name FROM hosts WHERE user_count != 0 AND sudo_enabled = false"
        );
        expected = [ "api-1" ]; # bob is developer on api-1, no sudo
      };

      # "Hosts with monitoring enabled"
      test-sql-monitoring = {
        expr = builtins.length (qhc "SELECT name FROM hosts WHERE monitoring_enabled = true");
        expected = 4; # all servers are prod
      };

      # "Hosts with cron jobs"
      test-sql-cron-hosts = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.name) (qhc "SELECT name FROM hosts WHERE cron_job_count != 0")
        );
        expected = [
          "db-1"
          "web-1"
        ];
      };

      # ─── Comparison operators (>, >=, <, <=) ───

      # "Servers with more than 4 cores"
      test-sql-gt-cores = {
        expr = map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE cores > 4");
        expected = [ "db-1" ]; # db-1 has 8 cores
      };

      # "Servers with at least 16GB RAM"
      test-sql-gte-ram = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE ram_gb >= 16")
        );
        expected = [
          "api-1"
          "db-1"
        ]; # api-1 has 16, db-1 has 32
      };

      # "Ports below 1024"
      test-sql-lt-ports = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.number) (sql.query "SELECT number FROM ports WHERE number < 1024")
        );
        expected = [
          80
          443
        ];
      };

      # "Servers with 4 or fewer cores"
      test-sql-lte-cores = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE cores <= 4")
        );
        expected = [
          "api-1"
          "web-1"
          "web-2"
        ];
      };

      # Combined: "High-spec servers in us-east-1"
      test-sql-gt-and = {
        expr = map (r: r.hostname) (
          sql.query "SELECT hostname FROM servers WHERE cores > 4 AND datacenter = 'us-east-1'"
        );
        expected = [ "db-1" ];
      };

      # ─── LIKE operator ───

      # "Servers with hostnames starting with 'web'"
      test-sql-like-prefix = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE hostname LIKE 'web%'")
        );
        expected = [
          "web-1"
          "web-2"
        ];
      };

      # "Servers with hostnames ending with '-1'"
      test-sql-like-suffix = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE hostname LIKE '%-1'")
        );
        expected = [
          "api-1"
          "db-1"
          "web-1"
        ];
      };

      # "Servers with hostnames containing 'b'"
      test-sql-like-contains = {
        expr = builtins.sort builtins.lessThan (
          map (r: r.hostname) (sql.query "SELECT hostname FROM servers WHERE hostname LIKE '%b%'")
        );
        expected = [
          "db-1"
          "web-1"
          "web-2"
        ];
      };

      # "Full config summary: hostname, services, users"
      test-sql-config-summary = {
        expr =
          let
            r = builtins.head (
              qhc "SELECT hostname, nginx_enabled, postgresql_enabled, sudo_enabled, user_count FROM hosts WHERE name = 'web-1'"
            );
          in
          {
            inherit (r)
              hostname
              nginx_enabled
              postgresql_enabled
              sudo_enabled
              user_count
              ;
          };
        expected = {
          hostname = "web-1";
          nginx_enabled = true;
          postgresql_enabled = false;
          sudo_enabled = true;
          user_count = 1;
        };
      };
    };

  rules =
    let
      configs = sql.hostConfigs;
    in
    {
      # All servers get SSH (no WHERE = matches all)
      test-all-servers-have-ssh = {
        expr = builtins.all (name: configs.${name}.services.openssh.enable or false) (
          builtins.attrNames configs
        );
        expected = true;
      };

      # web-1 gets nginx (tagged "web")
      test-web1-has-nginx = {
        expr = configs.web-1.services.nginx.enable or false;
        expected = true;
      };

      # db-1 gets postgresql (tagged "database")
      test-db1-has-postgresql = {
        expr = configs.db-1.services.postgresql.enable or false;
        expected = true;
      };

      # db-1 does NOT get nginx (not tagged "web")
      test-db1-no-nginx = {
        expr = configs.db-1.services.nginx.enable or false;
        expected = false;
      };

      # web-1 gets ACME (has exposed port 443 via nginx)
      test-web1-has-acme = {
        expr = configs.web-1.security.acme.acceptTerms or false;
        expected = true;
      };

      # api-1 does NOT get ACME (port 50051 is not 443)
      test-api1-no-acme = {
        expr = configs.api-1.security.acme.acceptTerms or false;
        expected = false;
      };

      # web-1 gets sudo (alice has admin role, assigned to web-1)
      test-web1-has-sudo = {
        expr = configs.web-1.security.sudo.enable or false;
        expected = true;
      };

      # api-1 does NOT get sudo (bob is developer, no sudo)
      test-api1-no-sudo = {
        expr = configs.api-1.security.sudo.enable or false;
        expected = false;
      };

      # All prod servers get monitoring
      test-prod-servers-have-monitoring = {
        expr = builtins.all (name: configs.${name}.services.prometheus.exporters.node.enable or false) (
          builtins.attrNames configs
        );
        expected = true;
      };

      # Base module still present (hostname from nixos.nix)
      test-base-module-preserved = {
        expr = configs.web-1.networking.hostName;
        expected = "web-1";
      };

      # Base firewall ports still present after rule merge
      test-base-firewall-preserved = {
        expr = builtins.sort builtins.lessThan (configs.web-1.networking.firewall.allowedTCPPorts);
        expected = [
          80
          443
        ];
      };
    };

  fixpoint =
    let
      configs = sql.hostConfigs;
    in
    {
      # Fixpoint convergence: web servers get enriched with has-nginx,
      # then nginx-monitoring rule fires on the enriched context
      test-web-has-nginx-monitoring = {
        expr = configs.web-1.services.prometheus.exporters.nginx.enable or false;
        expected = true;
      };

      test-db-no-nginx-monitoring = {
        expr = configs.db-1.services.prometheus.exporters.nginx.enable or false;
        expected = false;
      };

      test-api-no-nginx-monitoring = {
        expr = configs.api-1.services.prometheus.exporters.nginx.enable or false;
        expected = false;
      };

      # web-2 also tagged "web" so should also get nginx monitoring
      test-web2-has-nginx-monitoring = {
        expr = configs.web-2.services.prometheus.exporters.nginx.enable or false;
        expected = true;
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
      expected = [
        "db-1"
        "web-1"
        "web-2"
      ];
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
          sudoEntries = lib.filterAttrs (
            _: ea: builtins.elem "sudo" ea.actions && lib.hasPrefix "server:" ea.resource
          ) sql.effectiveAccess;
          serverNames = map (ea: lib.removePrefix "server:" ea.resource) (builtins.attrValues sudoEntries);
        in
        builtins.sort builtins.lessThan serverNames;
      expected = [
        "db-1"
        "web-1"
      ];
    };
  };

  # ─── Cross-library bridge demos ─────────────────────────────────
  # Showcases all 8 gen-* libraries in cross-library pipeline queries:
  #   gen-algebra, gen-schema, gen-scope, gen-graph,
  #   gen-select, gen-derive, gen-bind, nixpkgs lib

  bridge =
    let
      sel = sql.selectLib;
    in
    {
      # Pipeline 1: gen-select selector → filter instance graph nodes
      # "Which server-type nodes are in the instance graph?"
      test-select-to-graph = {
        expr =
          let
            prodSelector = sel.when (_id: ctx: (ctx.data _id).type == "server");
            ctx = {
              data = id: sql.instanceNodes.nodeData id;
              parent = _: null;
              children = _: [ ];
              ancestors = _: [ ];
              siblings = _: [ ];
            };
            serverNodes = builtins.filter (id: lib.hasPrefix "server:" id) sql.instanceNodes.nodes;
            matching = builtins.filter (id: sel.matches prodSelector id ctx) serverNodes;
          in
          builtins.sort builtins.lessThan matching;
        expected = [
          "server:api-1"
          "server:db-1"
          "server:web-1"
          "server:web-2"
        ];
      };

      # Pipeline 2: gen-select selector → gen-derive dispatch → action
      test-selector-derive-dispatch = {
        expr =
          let
            inherit (sql.deriveLib) mkRule dispatch entryAnywhere;
            match = sql.deriveLib.adapters.select.mkMatch sel;
            testRule = mkRule {
              condition = sel.when (_id: ctx: builtins.elem "web" ((ctx.data _id).tags or [ ]));
              produce = _id: _ctx: [
                {
                  __action = "tagged";
                  value = true;
                }
              ];
              identity = "bridge-test";
            };
            serverCtx = sql.mkServerContext {
              tags = [
                "web"
                "proxy"
              ];
              environment = "prod";
            };
            result = dispatch {
              rules = [ testRule ];
              id = "test-server";
              context = serverCtx;
              inherit match;
              classify = _: "default";
              phases = {
                default = entryAnywhere { };
              };
            };
          in
          builtins.length (result.actions.default or [ ]) > 0;
        expected = true;
      };

      # Pipeline 3: gen-schema introspection → gen-graph reachability
      # "Which schema kinds are reachable from 'server' via ref/parent edges?"
      test-schema-graph-reachability = {
        expr =
          let
            reachable = graphLib.reachableFrom sql.kindNodes "server";
          in
          builtins.sort builtins.lessThan reachable;
        expected = [
          "datacenter"
          "environment"
          "network"
          "subnet"
        ];
      };
    };
}
