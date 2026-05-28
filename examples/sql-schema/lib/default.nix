{
  lib,
  schemaLib,
  graphLib,
  selectLib,
  deriveLib,
  bindLib,
}:
let
  rawFleet = import ./fleet.nix;
  schemaModule = import ./schema.nix { inherit lib schemaLib; };
  evaluated = schemaModule.evalSchema rawFleet;

  # Graph construction: kind-level and instance-level
  # Bridge from gen-schema introspection to gen-scope/gen-graph (consumer-side)
  kindNodes = graphLib.mock.mkGraph {
    edges = map (e: {
      from = e.from;
      to = e.to;
    }) evaluated.schema._edges;
    nodeData = lib.genAttrs evaluated.schema._kindNames (k: {
      type = "kind";
      kind = k;
    });
  };

  instanceNodes =
    let
      # Collect all instances with namespaced IDs
      allInstances = lib.concatMapAttrs (
        kindName: instances:
        lib.mapAttrs' (name: inst: {
          name = "${kindName}:${name}";
          value = {
            type = kindName;
            inherit name;
            data = inst;
          };
        }) instances
      ) evaluated.fleet;

      # Build edges from ref fields
      instanceEdges = lib.concatLists (
        lib.mapAttrsToList (
          kindName: instances:
          let
            refs = lib.mapAttrs (_: v: v.refKind) evaluated.schema.${kindName}.refs;
          in
          lib.concatLists (
            lib.mapAttrsToList (
              instName: inst:
              lib.concatLists (
                lib.mapAttrsToList (
                  refField: targetKind:
                  let
                    val = inst.${refField} or null;
                    targetName =
                      if val == null then
                        null
                      else if builtins.isString val then
                        val
                      else
                        val.name or null;
                  in
                  lib.optional (targetName != null) {
                    from = "${kindName}:${instName}";
                    to = "${targetKind}:${targetName}";
                  }
                ) refs
              )
            ) instances
          )
        ) evaluated.fleet
      );
    in
    graphLib.mock.mkGraph {
      edges = instanceEdges;
      nodeData = allInstances;
    };

  # SQL parser + engine
  sqlParser = import ./sql.nix { inherit lib; };
  sqlEngine = import ./engine.nix { inherit lib selectLib; };

  # DDL generator
  ddlLib = import ./ddl.nix { inherit lib schemaLib; };
  ddl = ddlLib.generateDDL evaluated.schema;

  # Synthesis
  aclLib = import ./acl.nix { inherit lib graphLib instanceNodes; };
  reachLib = import ./reachability.nix { inherit lib; };
  effectiveAccess = aclLib.synthesizeAccess rawFleet;
  networkReachability = reachLib.synthesizeReachability rawFleet;

  # NixOS configuration generation
  nixosLib = import ./nixos.nix {
    inherit lib bindLib;
  };

  # Rule-based host configuration (gen-derive stratified dispatch)
  rulesLib = import ./rules.nix {
    inherit lib deriveLib selectLib;
  };

  sel = selectLib;

  # Default demo rules — gen-derive mkRule with gen-select selectors
  demoRules = [
    # All servers get SSH (unconditional)
    (deriveLib.mkRule {
      condition = sel.star;
      produce = _id: _ctx: [ (rulesLib.fx.nixos { services.openssh.enable = true; }) ];
      identity = "ssh-everywhere";
    })

    # Web-tagged servers get nginx
    (deriveLib.mkRule {
      condition = sel.when (_id: ctx: builtins.elem "web" ((ctx.data _id).tags or [ ]));
      produce = _id: _ctx: [ (rulesLib.fx.nixos { services.nginx.enable = true; }) ];
      identity = "web-nginx";
    })

    # Database-tagged servers get postgresql
    (deriveLib.mkRule {
      condition = sel.when (_id: ctx: builtins.elem "database" ((ctx.data _id).tags or [ ]));
      produce = _id: _ctx: [ (rulesLib.fx.nixos { services.postgresql.enable = true; }) ];
      identity = "db-postgresql";
    })

    # ACME certs: servers with exposed port 443
    (deriveLib.mkRule {
      condition = sel.when (
        id: _ctx:
        let
          rows = sqlEngine.query rawFleet "SELECT s.name FROM servers s JOIN services svc ON svc.server = s.name JOIN ports p ON p.service = svc.name WHERE p.expose = true AND p.number = 443";
        in
        builtins.any (r: (r.name or r) == id) rows
      );
      produce = _id: _ctx: [ (rulesLib.fx.nixos { security.acme.acceptTerms = true; }) ];
      identity = "acme-certs";
    })

    # Admin-role users on server get sudo
    (deriveLib.mkRule {
      condition = sel.when (
        id: _ctx:
        let
          adminUsers = lib.filterAttrs (
            _: u: (u.ldap-role or "") == "admin" && builtins.elem id (u.servers or [ ])
          ) (rawFleet.user or { });
        in
        adminUsers != { }
      );
      produce = _id: _ctx: [ (rulesLib.fx.nixos { security.sudo.enable = true; }) ];
      identity = "admin-sudo";
    })

    # Prod servers get monitoring
    (deriveLib.mkRule {
      condition = sel.when (_id: ctx: (ctx.data _id).environment == "prod");
      produce = _id: _ctx: [
        (rulesLib.fx.nixos { services.prometheus.exporters.node.enable = true; })
      ];
      identity = "prod-monitoring";
    })

    # --- Fixpoint convergence demo ---
    # Pass 1: web servers get enrichment flag
    (deriveLib.mkRule {
      condition = sel.when (_id: ctx: builtins.elem "web" ((ctx.data _id).tags or [ ]));
      produce = _id: _ctx: [
        (rulesLib.fx.enrich {
          key = "has-nginx";
          value = true;
        })
      ];
      identity = "nginx-enrichment";
    })

    # Pass 2: fires only after enrichment adds has-nginx to context
    (deriveLib.mkRule {
      condition = sel.when (_id: ctx: (ctx.data _id).has-nginx or false);
      produce = _id: _ctx: [
        (rulesLib.fx.nixos { services.prometheus.exporters.nginx.enable = true; })
      ];
      identity = "nginx-monitoring";
    })
  ];

  # Host configs: base modules (from nixos.nix) + gen-derive rule output
  hostConfigs = lib.mapAttrs (
    name: _:
    let
      base = nixosLib.evalServerModule rawFleet name;
      ruleConfig = rulesLib.buildHostConfig evaluated.fleet demoRules name;
    in
    lib.recursiveUpdate base ruleConfig
  ) (rawFleet.server or { });

  # SQL queries against the rendered NixOS configs
  queryHostConfigs = nixosLib.queries.queryConfigs sqlEngine.query hostConfigs;
in
{
  inherit (schemaModule) refinements validators;
  inherit (evaluated) schema fleet;
  evalSchema = schemaModule.evalSchema;
  inherit rawFleet;

  # Graph API
  inherit kindNodes instanceNodes;

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
  inherit (nixosLib)
    buildServerModule
    evalServerModule
    buildAllModules
    evalServerConfig
    evalAllConfigs
    ;
  nixosModules = nixosLib.buildAllModules rawFleet;
  nixosConfigs = nixosLib.evalAllConfigs rawFleet;
  nixosQueries = nixosLib.queries;

  # Rule-based host configuration (gen-derive)
  inherit (rulesLib)
    fx
    phases
    match
    mkServerContext
    extract
    buildHostConfig
    buildAllHostConfigs
    ;
  inherit
    deriveLib
    selectLib
    bindLib
    graphLib
    demoRules
    ;
  inherit hostConfigs queryHostConfigs;
}
