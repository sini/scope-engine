# Feature flag scope graph with HOAG rollout synthesis.
#
# Hierarchy:
#   global                         (default flag values)
#   ├── org:acme                   (org-level overrides)
#   │   ├── project:alpha          (project-level overrides)
#   │   │   ├── user:alice
#   │   │   └── user:bob
#   │   └── project:beta
#   │       └── user:carol
#   └── org:widgets
#       └── project:gamma
#           └── user:dave
#
# Flags:
#   dark-mode      — global=false, org:acme=true
#   new-editor     — global=false, project:alpha=true, user:bob=false
#   ai-assist      — global=false, depends on new-editor
#   beta-features  — global=false, org:widgets=true
#   max-items      — global=50, project:alpha=100
{ engine, lib }:
let
  baseNodes = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.star "global" [ "org:acme" "org:widgets" ])
      (engine.star "org:acme" [ "project:alpha" "project:beta" ])
      (engine.star "project:alpha" [ "user:alice" "user:bob" ])
      (engine.edge "user:carol" "project:beta")
      (engine.edge "project:gamma" "org:widgets")
      (engine.edge "user:dave" "project:gamma")
    ];
    decls = {
      global = { dark-mode = false; new-editor = false; ai-assist = false; beta-features = false; max-items = 50; };
      "org:acme" = { dark-mode = true; };
      "org:widgets" = { beta-features = true; };
      "project:alpha" = { new-editor = true; max-items = 100; };
      "project:beta" = { }; "project:gamma" = { };
      "user:alice" = { }; "user:bob" = { new-editor = false; };
      "user:carol" = { }; "user:dave" = { };
    };
    types = {
      global = "global";
      "org:acme" = "org"; "org:widgets" = "org";
      "project:alpha" = "project"; "project:beta" = "project"; "project:gamma" = "project";
      "user:alice" = "user"; "user:bob" = "user"; "user:carol" = "user"; "user:dave" = "user";
    };
  };

  # HOAG synthesis: rollout tracking nodes for beta-enabled orgs (Vogt 1989).
  synthesize = self:
    let orgs = lib.filterAttrs (_: n: n.type == "org") self.nodes;
    in lib.concatMapAttrs (id: node:
      if (node.decls.beta-features or false) then {
        "rollout:${id}" = {
          inherit id; parent = id;
          decls = { stage = "canary"; targetPct = 100; };
          imports = [ ]; childrenIds = [ ]; type = "rollout";
          edgesByLabel = { }; rels = { };
        };
      } else { }
    ) orgs;
in
{ inherit baseNodes synthesize; }
