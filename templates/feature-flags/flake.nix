{
  description = "Feature flag evaluator: hierarchical flag resolution with rollout rules";

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
      # Feature flag evaluator
      #
      # Flags are defined at hierarchy levels. Deeper levels override
      # shallower ones. HOAG synthesis creates computed rollout rules.
      # Circular attributes resolve flag dependencies.
      #
      # Hierarchy:
      #   global                         (default flag values)
      #   ├── org:acme                   (org-level overrides)
      #   │   ├── project:alpha          (project-level overrides)
      #   │   │   ├── user:alice         (user-level overrides)
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
      # ═══════════════════════════════════════════════════════════════

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
          global = {
            dark-mode = false;
            new-editor = false;
            ai-assist = false;
            beta-features = false;
            max-items = 50;
          };
          "org:acme" = { dark-mode = true; };
          "org:widgets" = { beta-features = true; };
          "project:alpha" = { new-editor = true; max-items = 100; };
          "project:beta" = {};
          "project:gamma" = {};
          "user:alice" = {};
          "user:bob" = { new-editor = false; };   # Bob opts out of new-editor
          "user:carol" = {};
          "user:dave" = {};
        };
        types = {
          global = "global";
          "org:acme" = "org"; "org:widgets" = "org";
          "project:alpha" = "project"; "project:beta" = "project"; "project:gamma" = "project";
          "user:alice" = "user"; "user:bob" = "user"; "user:carol" = "user"; "user:dave" = "user";
        };
      };

      attributes = {
        # Resolve a flag value: walks hierarchy, deepest wins.
        flag = engine.paramAttr (self: id: flagName:
          engine.query {
            dataFilter = node:
              if node.decls ? ${flagName} then node.decls.${flagName}
              else null;
          } self id);

        # All effective flags for a context (merge all levels).
        effectiveFlags = self: id:
          let
            node = self.nodes.${id};
            local = node.decls;
            parentFlags =
              if node.parent != null
              then self.evaluated.${node.parent}.get "effectiveFlags"
              else {};
          in engine.shadow local parentFlags;

        # Flag with dependency: ai-assist requires new-editor to be true.
        # If new-editor is off, ai-assist is forced off regardless.
        flagWithDeps = engine.paramAttr (self: id: flagName:
          let
            raw = self.evaluated.${id}.get "flag" flagName;
            deps = {
              ai-assist = [ "new-editor" ];  # ai-assist depends on new-editor
            };
            flagDeps = deps.${flagName} or [];
            allDepsMet = builtins.all
              (dep: self.evaluated.${id}.get "flag" dep == true)
              flagDeps;
          in if flagDeps == [] then raw
             else raw && allDepsMet);

        # Count how many flags differ from global defaults at this level.
        overrideCount = self: id:
          let
            effective = self.evaluated.${id}.get "effectiveFlags";
            defaults = self.nodes.global.decls;
          in builtins.length (builtins.filter (key:
            effective.${key} != (defaults.${key} or null)
          ) (builtins.attrNames defaults));

        # Rollout percentage simulation: converge via circular attribute.
        # Start at 0%, increase by 25% per iteration until target.
        rolloutPct = engine.circular { init = 0; } (
          self: id: prev:
          let target = 100;
          in if prev >= target then target
             else let next = prev + 25;
                  in if next > target then target else next);
      };

      # HOAG synthesis: create computed rollout nodes for orgs.
      # If an org has beta-features=true, synthesize a rollout tracking node.
      synthesize = self:
        let
          orgs = lib.filterAttrs (_: n: n.type == "org") self.nodes;
        in lib.concatMapAttrs (id: node:
          if (node.decls.beta-features or false) then {
            "rollout:${id}" = {
              inherit id; parent = id;
              decls = { stage = "canary"; targetPct = 100; };
              imports = []; childrenIds = [];
              type = "rollout";
              edgesByLabel = {}; rels = {};
            };
          } else {}
        ) orgs;

      result = engine.eval { inherit baseNodes attributes synthesize; };

    in
    {
      # ─── Flag resolution: hierarchy override ────────────────────────

      # Alice: dark-mode=true (from org:acme), new-editor=true (from project:alpha)
      tests.alice-dark-mode =
        result.evaluated."user:alice".get "flag" "dark-mode";
        # → true

      tests.alice-new-editor =
        result.evaluated."user:alice".get "flag" "new-editor";
        # → true

      # Bob: new-editor=false (explicit user-level opt-out)
      tests.bob-new-editor =
        result.evaluated."user:bob".get "flag" "new-editor";
        # → false

      # Carol: dark-mode=true (from org:acme), new-editor=false (global default)
      tests.carol-dark-mode =
        result.evaluated."user:carol".get "flag" "dark-mode";
        # → true

      tests.carol-new-editor =
        result.evaluated."user:carol".get "flag" "new-editor";
        # → false

      # Dave: beta-features=true (from org:widgets)
      tests.dave-beta =
        result.evaluated."user:dave".get "flag" "beta-features";
        # → true

      tests.dave-dark-mode =
        result.evaluated."user:dave".get "flag" "dark-mode";
        # → false (global default, org:widgets doesn't override)

      # max-items: project:alpha=100, everyone else=50
      tests.alice-max-items =
        result.evaluated."user:alice".get "flag" "max-items";
        # → 100

      tests.carol-max-items =
        result.evaluated."user:carol".get "flag" "max-items";
        # → 50

      # ─── Flag dependencies ─────────────────────────────────────────

      # ai-assist depends on new-editor. Alice has new-editor=true.
      tests.alice-ai-assist =
        result.evaluated."user:alice".get "flagWithDeps" "ai-assist";
        # → false (ai-assist itself is false globally, no override)

      # Even if we set ai-assist=true, Bob has new-editor=false so it stays false
      tests.bob-ai-assist-blocked =
        let
          # Simulate: pretend ai-assist is true at project level
          # Bob still can't use it because new-editor is false for him
          bobEditor = result.evaluated."user:bob".get "flag" "new-editor";
        in !bobEditor;
        # → true (new-editor is off, so ai-assist would be blocked)

      # ─── Effective flags (full merge) ───────────────────────────────

      tests.alice-effective =
        let f = result.evaluated."user:alice".get "effectiveFlags";
        in {
          dark-mode = f.dark-mode;
          new-editor = f.new-editor;
          max-items = f.max-items;
          beta-features = f.beta-features;
        };
        # → { dark-mode = true; new-editor = true; max-items = 100; beta-features = false; }

      tests.dave-effective =
        let f = result.evaluated."user:dave".get "effectiveFlags";
        in {
          dark-mode = f.dark-mode;
          beta-features = f.beta-features;
        };
        # → { dark-mode = false; beta-features = true; }

      # ─── Override counting ──────────────────────────────────────────

      # project:alpha: 3 flags differ from global (dark-mode from org, new-editor + max-items local)
      tests.alpha-override-count =
        result.evaluated."project:alpha".get "overrideCount";
        # → 3

      # global overrides 0 (it IS the defaults)
      tests.global-override-count =
        result.evaluated.global.get "overrideCount";
        # → 0

      # ─── HOAG synthesis: rollout tracking ───────────────────────────

      # org:widgets has beta-features=true → synthesized rollout node
      tests.rollout-exists =
        result.nodes ? "rollout:org:widgets";
        # → true

      # org:acme does NOT have beta-features → no rollout node
      tests.no-rollout-acme =
        !(result.nodes ? "rollout:org:acme");
        # → true

      tests.rollout-stage =
        result.nodes."rollout:org:widgets".decls.stage;
        # → "canary"

      # ─── Circular attribute: rollout convergence ────────────────────

      tests.rollout-converged =
        result.evaluated.global.get "rolloutPct";
        # → 100 (converges: 0 → 25 → 50 → 75 → 100)

      # ─── Typed queries ──────────────────────────────────────────────

      tests.all-users =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "user"));
        # → [ "user:alice" "user:bob" "user:carol" "user:dave" ]

      tests.all-orgs =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "org"));
        # → [ "org:acme" "org:widgets" ]

      tests.rollout-nodes =
        builtins.attrNames (engine.nodesByType result "rollout");
        # → [ "rollout:org:widgets" ]

      # ─── Structural queries ─────────────────────────────────────────

      tests.alice-path =
        engine.ancestors result "user:alice";
        # → [ "project:alpha" "org:acme" "global" ]

      tests.acme-projects =
        builtins.sort builtins.lessThan (engine.childrenIds result "org:acme");
        # → [ "project:alpha" "project:beta" ]

      tests.alpha-users =
        builtins.sort builtins.lessThan (engine.childrenIds result "project:alpha");
        # → [ "user:alice" "user:bob" ]

      tests.is-alice-under-acme =
        engine.isAncestor result "org:acme" "user:alice";
        # → true

      tests.is-dave-under-acme =
        engine.isAncestor result "org:acme" "user:dave";
        # → false
    };
}
