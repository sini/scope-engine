# Package dependency resolver scope graph.
#
# Packages form a dependency graph. Each package declares its version
# and exports. Dependencies create import edges. HOAG synthesis computes
# resolved dependency sets. Ambiguity detection catches version conflicts.
#
# Package graph:
#   workspace (root)
#   ├── app@1.0 → depends on: lib-http@2.x, lib-json@1.x
#   ├── lib-http@2.3 → depends on: lib-json@1.x, lib-tls@1.x
#   ├── lib-json@1.5
#   ├── lib-json@2.0    ← conflict: app wants 1.x, but exists
#   ├── lib-tls@1.2
#   └── lib-logging@3.1 → depends on: lib-json@1.x
{ engine, lib }:
let
  roots = engine.buildNodes {
    parentGraph = engine.star "workspace" [
      "app@1.0"
      "lib-http@2.3"
      "lib-json@1.5"
      "lib-json@2.0"
      "lib-tls@1.2"
      "lib-logging@3.1"
    ];
    importGraph = engine.overlays [
      (engine.edge "app@1.0" "lib-http@2.3")
      (engine.edge "app@1.0" "lib-json@1.5")
      (engine.edge "lib-http@2.3" "lib-json@1.5")
      (engine.edge "lib-http@2.3" "lib-tls@1.2")
      (engine.edge "lib-logging@3.1" "lib-json@1.5")
    ];
    edgeGraphs = {
      # D = devDependency (separate from runtime deps)
      D = engine.edge "app@1.0" "lib-logging@3.1";
    };
    decls = {
      workspace = {
        name = "my-workspace";
      };
      "app@1.0" = {
        name = "app";
        version = "1.0";
        exports = [
          "main"
          "cli"
        ];
      };
      "lib-http@2.3" = {
        name = "lib-http";
        version = "2.3";
        exports = [
          "get"
          "post"
          "request"
        ];
      };
      "lib-json@1.5" = {
        name = "lib-json";
        version = "1.5";
        exports = [
          "parse"
          "stringify"
        ];
      };
      "lib-json@2.0" = {
        name = "lib-json";
        version = "2.0";
        exports = [
          "parse"
          "stringify"
          "stream"
        ];
      };
      "lib-tls@1.2" = {
        name = "lib-tls";
        version = "1.2";
        exports = [
          "connect"
          "verify"
        ];
      };
      "lib-logging@3.1" = {
        name = "lib-logging";
        version = "3.1";
        exports = [
          "info"
          "warn"
          "error"
        ];
      };
    };
    types = {
      workspace = "workspace";
      "app@1.0" = "app";
      "lib-http@2.3" = "lib";
      "lib-json@1.5" = "lib";
      "lib-json@2.0" = "lib";
      "lib-tls@1.2" = "lib";
      "lib-logging@3.1" = "lib";
    };
  };

  # Build attributes with children that include synthesized manifest nodes
  mkAttributes =
    rootNodes: userAttrs:
    let
      baseAttrs = {
        children =
          self: id:
          let
            staticChildren = lib.filterAttrs (_: n: n.parent == id) rootNodes;
          in
          staticChildren;
        imports = _self: id: (_self.node id).decls.__edges.I or [ ];
        "edges-D" = _self: id: (_self.node id).decls.__edges.D or [ ];
      };
      # Derived children: synthesize manifest node for app
      derivedAttrs = {
        derived-children =
          self: id:
          if id == "workspace" then
            {
              "resolved:app@1.0" = {
                id = "resolved:app@1.0";
                parent = "workspace";
                decls = {
                  package = "app@1.0";
                  resolvedDeps = self.get "app@1.0" "allDeps";
                  totalAPIs = self.get "app@1.0" "availableAPIs";
                };
                type = "manifest";
              };
            }
          else
            { };
      };
    in
    baseAttrs // derivedAttrs // userAttrs;
in
{
  inherit roots mkAttributes;
}
