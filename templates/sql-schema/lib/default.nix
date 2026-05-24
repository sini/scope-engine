{
  lib,
  engine,
  schemaLib,
  graphLib,
  genLib,
}:
let
  rawFleet = import ./fleet.nix;
  schemaModule = import ./schema.nix { inherit lib schemaLib; };
  evaluated = schemaModule.evalSchema rawFleet;

  # Graph construction: kind-level and instance-level
  kindGraphInputs = schemaLib.buildKindGraph evaluated.schema;
  kindNodes = engine.buildNodes kindGraphInputs;

  instanceGraphInputs = schemaLib.buildInstanceGraph evaluated.schema evaluated.fleet;
  instanceNodes = engine.buildNodes instanceGraphInputs;

  # SQL parser + engine
  sqlParser = import ./sql.nix { inherit lib; };
  sqlEngine = import ./engine.nix { inherit lib; };

  # DDL generator
  ddlLib = import ./ddl.nix { inherit lib schemaLib; };
  ddl = ddlLib.generateDDL evaluated.schema;

  # Synthesis
  aclLib = import ./acl.nix { inherit lib; };
  reachLib = import ./reachability.nix { inherit lib; };
  effectiveAccess = aclLib.synthesizeAccess rawFleet;
  networkReachability = reachLib.synthesizeReachability rawFleet;

  # NixOS configuration generation
  nixosLib = import ./nixos.nix { inherit lib; queryFn = sqlEngine.query; };

  # Rule-based host configuration
  rulesLib = import ./rules.nix { inherit lib; queryFn = sqlEngine.query; };

  # Default demo rules — SQL WHERE → NixOS modules
  demoRules = [
    # All servers get SSH (no WHERE = matches all)
    { nixos = { services.openssh.enable = true; }; }

    # Web-tagged servers get nginx
    { where = "tags IN ('web')";
      nixos = { services.nginx.enable = true; }; }

    # Database-tagged servers get postgresql
    { where = "tags IN ('database')";
      nixos = { services.postgresql.enable = true; }; }

    # Servers with exposed port 443 get ACME certs
    { where = "SELECT s.name FROM servers s JOIN services svc ON svc.server = s.name JOIN ports p ON p.service = svc.name WHERE p.expose = true AND p.number = 443";
      nixos = { security.acme.acceptTerms = true; }; }

    # Servers with admin-role users get sudo enabled
    # Uses match function: the "servers" field on users is setOf (list),
    # which the SQL JOIN engine can't traverse — so use Nix predicate.
    { match = { fleet, serverName, ... }:
        let
          adminUsers = lib.filterAttrs (_: u:
            (u.ldap-role or "") == "admin" && builtins.elem serverName (u.servers or [])
          ) (fleet.user or {});
        in adminUsers != {};
      nixos = { security.sudo.enable = true; }; }

    # Prod servers get monitoring
    { where = "environment = 'prod'";
      nixos = { services.prometheus.exporters.node.enable = true; }; }
  ];
in
{
  inherit (schemaModule) refinements validators;
  inherit (evaluated) schema fleet;
  evalSchema = schemaModule.evalSchema;
  inherit rawFleet;

  # Graph API
  inherit kindNodes instanceNodes;
  inherit kindGraphInputs instanceGraphInputs;

  # gen-graph queries on kind-level graph
  kindRoots = graphLib.roots kindNodes;
  kindLeaves = graphLib.leaves kindNodes;
  kindCycles = graphLib.cycles kindNodes;
  kindMigrationOrder = graphLib.roots kindNodes;

  # gen-graph queries on instance-level graph
  reachableFrom = graphLib.reachableFrom instanceNodes;
  dependents = graphLib.dependents instanceNodes;
  impactOf = graphLib.impactOf instanceNodes;

  # SQL parser + engine
  inherit (sqlParser) parseSql tokenize;
  query = sqlEngine.query rawFleet;
  queryFleet = sqlEngine.query;

  # DDL
  inherit ddl;
  generateDDL = ddlLib.generateDDL;
  migrationOrder = ddlLib.migrationOrder evaluated.schema;
  inherit (ddlLib) escapeIdent;

  # Synthesis
  inherit effectiveAccess networkReachability;
  synthesizeAccess = aclLib.synthesizeAccess;
  synthesizeReachability = reachLib.synthesizeReachability;

  # NixOS configuration generation
  inherit (nixosLib) buildServerModule buildAllModules evalServerConfig evalAllConfigs;
  nixosModules = nixosLib.buildAllModules rawFleet;
  nixosConfigs = nixosLib.evalAllConfigs rawFleet;
  nixosQueries = nixosLib.queries;

  # Rule-based host configuration
  inherit (rulesLib) ruleMatchesServer matchingModules buildHostConfig buildAllHostConfigs;
  inherit demoRules;
  hostConfigs = rulesLib.buildAllHostConfigs rawFleet demoRules nixosLib.buildServerModule;
}
