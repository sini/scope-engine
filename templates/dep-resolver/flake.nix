{
  description = "Dependency resolver: package resolution with version constraints and conflict detection";

  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };

      # ═══════════════════════════════════════════════════════════════
      # Package dependency resolver
      #
      # Packages form a dependency graph. Each package declares its
      # version and exports. Dependencies create import edges.
      # HOAG synthesis computes resolved dependency sets.
      # Ambiguity detection catches version conflicts.
      #
      # Package graph:
      #   workspace (root)
      #   ├── app@1.0 → depends on: lib-http@2.x, lib-json@1.x
      #   ├── lib-http@2.3 → depends on: lib-json@1.x, lib-tls@1.x
      #   ├── lib-json@1.5
      #   ├── lib-json@2.0    ← conflict: app wants 1.x, but exists
      #   ├── lib-tls@1.2
      #   └── lib-logging@3.1 → depends on: lib-json@1.x
      # ═══════════════════════════════════════════════════════════════

      baseNodes = engine.buildNodes {
        # Workspace contains all packages
        parentGraph = engine.star "workspace" [
          "app@1.0" "lib-http@2.3" "lib-json@1.5" "lib-json@2.0"
          "lib-tls@1.2" "lib-logging@3.1"
        ];
        # Dependencies as import edges
        importGraph = engine.overlays [
          # app depends on lib-http and lib-json@1.5
          (engine.edge "app@1.0" "lib-http@2.3")
          (engine.edge "app@1.0" "lib-json@1.5")
          # lib-http depends on lib-json@1.5 and lib-tls
          (engine.edge "lib-http@2.3" "lib-json@1.5")
          (engine.edge "lib-http@2.3" "lib-tls@1.2")
          # lib-logging depends on lib-json@1.5
          (engine.edge "lib-logging@3.1" "lib-json@1.5")
        ];
        edgeGraphs = {
          # D = devDependency (separate from runtime deps)
          D = engine.edge "app@1.0" "lib-logging@3.1";
        };
        decls = {
          workspace = { name = "my-workspace"; };
          "app@1.0" = { name = "app"; version = "1.0"; exports = [ "main" "cli" ]; };
          "lib-http@2.3" = { name = "lib-http"; version = "2.3"; exports = [ "get" "post" "request" ]; };
          "lib-json@1.5" = { name = "lib-json"; version = "1.5"; exports = [ "parse" "stringify" ]; };
          "lib-json@2.0" = { name = "lib-json"; version = "2.0"; exports = [ "parse" "stringify" "stream" ]; };
          "lib-tls@1.2" = { name = "lib-tls"; version = "1.2"; exports = [ "connect" "verify" ]; };
          "lib-logging@3.1" = { name = "lib-logging"; version = "3.1"; exports = [ "info" "warn" "error" ]; };
        };
        types = {
          workspace = "workspace";
          "app@1.0" = "app";
          "lib-http@2.3" = "lib"; "lib-json@1.5" = "lib"; "lib-json@2.0" = "lib";
          "lib-tls@1.2" = "lib"; "lib-logging@3.1" = "lib";
        };
      };

      attributes = {
        # All available APIs: own exports + transitive dependency exports
        availableAPIs = self: id:
          let
            node = self.nodes.${id};
            own = node.decls.exports or [];
            imported = engine.collectImports
              (self: iid: self.evaluated.${iid}.get "availableAPIs")
              self id;
          in lib.unique (own ++ imported);

        # Dependency depth: longest chain to a leaf
        depDepth = self: id:
          let
            node = self.nodes.${id};
            childDepths = map
              (iid: self.evaluated.${iid}.get "depDepth")
              node.imports;
          in if childDepths == [] then 0
             else 1 + lib.foldl' (a: b: if a > b then a else b) 0 childDepths;

        # Total transitive dependency count
        depCount = self: id:
          let
            direct = self.nodes.${id}.imports;
            transitive = lib.concatMap
              (iid: self.evaluated.${iid}.get "allDeps")
              direct;
          in builtins.length (lib.unique (direct ++ transitive));

        # All transitive dependencies (flat list)
        allDeps = self: id:
          let
            direct = self.nodes.${id}.imports;
            transitive = lib.concatMap
              (iid: self.evaluated.${iid}.get "allDeps")
              direct;
          in lib.unique (direct ++ transitive);
      };

      # HOAG synthesis: compute a "resolved" manifest node for app
      synthesize = self: {
        "resolved:app@1.0" = {
          id = "resolved:app@1.0";
          parent = "workspace";
          decls = {
            package = "app@1.0";
            resolvedDeps = self.evaluated."app@1.0".get "allDeps";
            totalAPIs = self.evaluated."app@1.0".get "availableAPIs";
          };
          imports = []; childrenIds = [];
          type = "manifest";
          edgesByLabel = {}; rels = {};
        };
      };

      result = engine.eval { inherit baseNodes attributes synthesize; };

    in
    {
      # ─── Dependency resolution ──────────────────────────────────────

      # Direct dependencies of app
      tests.app-direct-deps =
        result.nodes."app@1.0".imports;
        # → [ "lib-http@2.3" "lib-json@1.5" ]

      # Transitive deps: app → lib-http → lib-json + lib-tls
      tests.app-all-deps =
        builtins.sort builtins.lessThan
          (result.evaluated."app@1.0".get "allDeps");
        # → [ "lib-http@2.3" "lib-json@1.5" "lib-tls@1.2" ]

      tests.app-dep-count =
        result.evaluated."app@1.0".get "depCount";
        # → 3

      # Dep depth: app → lib-http → lib-json = depth 2
      tests.app-dep-depth =
        result.evaluated."app@1.0".get "depDepth";
        # → 2

      # Leaf packages have depth 0
      tests.json-dep-depth =
        result.evaluated."lib-json@1.5".get "depDepth";
        # → 0

      # ─── Available APIs (transitive exports) ────────────────────────

      tests.app-available-apis =
        builtins.sort builtins.lessThan
          (result.evaluated."app@1.0".get "availableAPIs");
        # → [ "cli" "connect" "get" "main" "parse" "post" "request" "stringify" "verify" ]

      tests.http-available-apis =
        builtins.sort builtins.lessThan
          (result.evaluated."lib-http@2.3".get "availableAPIs");
        # → [ "connect" "get" "parse" "post" "request" "stringify" "verify" ]

      # Leaf package: only own exports
      tests.tls-available-apis =
        result.evaluated."lib-tls@1.2".get "availableAPIs";
        # → [ "connect" "verify" ]

      # ─── Custom edge labels: devDependencies ────────────────────────

      tests.app-dev-deps =
        engine.followEdge "D" result "app@1.0";
        # → [ "lib-logging@3.1" ]

      tests.logging-not-in-runtime-deps =
        !(builtins.elem "lib-logging@3.1"
          (result.evaluated."app@1.0".get "allDeps"));
        # → true (logging is devDep, not runtime import)

      # ─── HOAG synthesis: resolved manifest ──────────────────────────

      tests.manifest-exists =
        result.nodes ? "resolved:app@1.0";
        # → true

      tests.manifest-resolved-deps =
        builtins.sort builtins.lessThan
          result.nodes."resolved:app@1.0".decls.resolvedDeps;
        # → [ "lib-http@2.3" "lib-json@1.5" "lib-tls@1.2" ]

      tests.manifest-type =
        result.nodes."resolved:app@1.0".type;
        # → "manifest"

      # ─── Version conflict detection ─────────────────────────────────

      # Both lib-json@1.5 and lib-json@2.0 exist in workspace.
      # Detect conflict: querying workspace for "lib-json" finds both versions.
      tests.json-version-conflict =
        let
          jsonVersions = engine.collect
            { filter = n: (n.decls.name or "") == "lib-json"; }
            (self: id: [ self.nodes.${id}.decls.version ])
            result;
        in builtins.sort builtins.lessThan jsonVersions;
        # → [ "1.5" "2.0" ] — two versions present

      tests.json-conflict-count =
        let
          jsonPkgs = engine.collect
            { filter = n: (n.decls.name or "") == "lib-json"; }
            (self: id: [ id ])
            result;
        in builtins.length jsonPkgs;
        # → 2

      # ─── Typed queries ──────────────────────────────────────────────

      tests.all-libs =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "lib"));
        # → [ "lib-http@2.3" "lib-json@1.5" "lib-json@2.0" "lib-logging@3.1" "lib-tls@1.2" ]

      tests.lib-count =
        builtins.length (builtins.attrNames (engine.nodesByType result "lib"));
        # → 5

      # ─── Structural queries ─────────────────────────────────────────

      tests.workspace-children =
        builtins.sort builtins.lessThan
          (engine.childrenIds result "workspace");
        # all packages are children of workspace

      tests.json-siblings =
        let sibs = engine.siblings result "lib-json@1.5";
        in builtins.elem "lib-json@2.0" sibs;
        # → true (both are children of workspace)

      # ─── evalDebug: cycle detection ─────────────────────────────────

      tests.debug-works =
        let
          debugResult = engine.evalDebug { inherit baseNodes attributes; };
        in debugResult.evaluated."app@1.0".get "depDepth";
        # → 2 (same result, but with cycle protection)
    };
}
