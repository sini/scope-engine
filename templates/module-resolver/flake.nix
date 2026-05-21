{
  description = "Module resolver: Neron 2015 LM-style module system with scope graphs";

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
      # LM-inspired module system (Neron 2015 §2.1, §3, §4)
      #
      # Modules form a scope hierarchy via parent edges (lexical nesting).
      # Imports create cross-scope visibility via import edges.
      # Declarations are resolved through the scope graph using the
      # resolution calculus with specificity D < I < P.
      #
      # program:
      #   module Std {
      #     module IO     { def print = "io.print"; def format = "io.format" }
      #     module Math   { def sqrt = "math.sqrt"; def pi = 3 }
      #     module String { import Math; def concat = "string.concat" }
      #   }
      #   module App {
      #     import Std.String
      #     def main = "app.main"
      #     module Sub {
      #       import Std.IO
      #       def helper = "sub.helper"
      #     }
      #   }
      #   module Cycle1 { import Cycle2 }
      #   module Cycle2 { import Cycle1 }
      # ═══════════════════════════════════════════════════════════════

      # Build the scope graph for the program above.
      # Parent edges encode lexical nesting; import edges encode module imports.
      parentGraph = engine.overlays [
        # Top-level modules under root
        (engine.star "root" [ "Std" "App" "Cycle1" "Cycle2" ])
        # Std submodules
        (engine.star "Std" [ "Std.IO" "Std.Math" "Std.String" ])
        # App submodule
        (engine.edge "App.Sub" "App")
      ];

      importGraph = engine.overlays [
        # String imports Math (for numeric formatting)
        (engine.edge "Std.String" "Std.Math")
        # App imports String
        (engine.edge "App" "Std.String")
        # App.Sub imports IO
        (engine.edge "App.Sub" "Std.IO")
        # Cyclic: Cycle1 ↔ Cycle2
        (engine.edge "Cycle1" "Cycle2")
        (engine.edge "Cycle2" "Cycle1")
      ];

      baseNodes = engine.buildNodes {
        inherit parentGraph importGraph;
        decls = {
          root = {};
          "Std" = {};
          "Std.IO" = { print = "io.print"; format = "io.format"; };
          "Std.Math" = { sqrt = "math.sqrt"; pi = 3; };
          "Std.String" = { concat = "string.concat"; };
          "App" = { main = "app.main"; };
          "App.Sub" = { helper = "sub.helper"; };
          "Cycle1" = { val = "c1"; };
          "Cycle2" = { val = "c2"; };
        };
        types = {
          root = "root";
          Std = "module"; "Std.IO" = "module"; "Std.Math" = "module"; "Std.String" = "module";
          App = "module"; "App.Sub" = "module";
          Cycle1 = "module"; Cycle2 = "module";
        };
      };

      # Attribute: resolve a name by walking scope graph
      attributes = {
        # Lookup a declaration name. Walks: local decls → imports → parent chain.
        lookup = engine.paramAttr (
          self: id: name:
          engine.query {
            dataFilter = node: node.decls.${name} or null;
          } self id
        );

        # All visible declarations from this scope (local + imports + parent).
        visibleDecls = self: id:
          let
            node = self.nodes.${id};
            local = node.decls;
            importedDecls = lib.foldl' (acc: iid:
              engine.shadow (self.nodes.${iid}.decls) acc
            ) {} node.imports;
            parentDecls =
              if node.parent != null
              then self.evaluated.${node.parent}.get "visibleDecls"
              else {};
          in engine.shadow local (engine.shadow importedDecls parentDecls);

        # Count modules reachable from this scope
        moduleCount = self: id:
          builtins.length (engine.descendants self id);
      };

      result = engine.eval { inherit baseNodes attributes; };

    in
    {
      # ─── Resolution: D < I < P specificity (Neron 2015 Fig. 2) ─────

      # Direct declaration
      tests.direct-lookup =
        result.evaluated."Std.IO".get "lookup" "print";
        # → "io.print"

      # Import resolution: App imports Std.String, finds concat
      tests.import-lookup =
        result.evaluated.App.get "lookup" "concat";
        # → "string.concat"

      # Inherited from parent: App.Sub can see App's declarations via P edge
      tests.parent-inherit =
        result.evaluated."App.Sub".get "lookup" "main";
        # → "app.main"

      # Import + parent: App.Sub imports IO, but parent App imports String.
      # App.Sub should see IO's print directly.
      tests.sub-import =
        result.evaluated."App.Sub".get "lookup" "print";
        # → "io.print"

      # Transitive imports: String imports Math, so App (which imports String)
      # can see Math's pi through transitive chain.
      tests.transitive-import =
        engine.query {
          dataFilter = n: n.decls.pi or null;
          transitiveImports = true;
        } result "App";
        # → 3

      # Non-transitive (default): App cannot see Math's pi
      tests.non-transitive =
        engine.query {
          dataFilter = n: n.decls.pi or null;
        } result "App";
        # → null

      # ─── Ambiguity detection (van Antwerpen 2018) ───────────────────

      # Std.String has local concat + imported pi from Math + parent (Std).
      # Querying for concat: only one source → not ambiguous.
      tests.not-ambiguous =
        engine.ambiguous {
          dataFilter = n: n.decls.concat or null;
        } result "Std.String";
        # → false

      # App.Sub can reach main from parent and helper locally — no overlap.
      # But if we ask for something both parent and import provide...
      tests.shadow-no-ambiguity =
        engine.ambiguous {
          dataFilter = n: n.decls.format or null;
        } result "App.Sub";
        # → false (only IO has format)

      # ─── Cyclic imports (Neron 2015 §2.4, rule X) ──────────────────

      # Cycle1 and Cycle2 mutually import. Seen-imports prevents divergence.
      tests.cycle-safe-c1 =
        engine.query {
          dataFilter = n: n.decls.val or null;
        } result "Cycle1";
        # → "c1" (local wins, import doesn't loop)

      tests.cycle-safe-c2 =
        engine.query {
          dataFilter = n: n.decls.val or null;
        } result "Cycle2";
        # → "c2"

      # queryAll on cyclic imports: each sees its own + the other's val
      tests.cycle-all-reachable =
        builtins.sort builtins.lessThan (
          engine.queryAll {
            dataFilter = n: n.decls.val or null;
          } result "Cycle1"
        );
        # → [ "c1" "c2" ]

      # ─── Shadowing (Neron 2015 §5, Def. 1) ─────────────────────────

      # visibleDecls composes local, import, and parent declarations with
      # inner-shadows-outer semantics.
      tests.visible-decls-app-sub =
        let decls = result.evaluated."App.Sub".get "visibleDecls";
        in {
          has-helper = decls ? helper;      # local
          has-main = decls ? main;          # from parent App
          has-print = decls ? print;        # from import IO
          has-format = decls ? format;      # from import IO
        };
        # → all true

      # ─── Structural queries ─────────────────────────────────────────

      tests.std-submodules =
        builtins.sort builtins.lessThan (engine.childrenIds result "Std");
        # → [ "Std.IO" "Std.Math" "Std.String" ]

      tests.app-sub-ancestors =
        engine.ancestors result "App.Sub";
        # → [ "App" "root" ]

      tests.module-count =
        result.evaluated.root.get "moduleCount";
        # → 8 (all descendants of root)

      tests.typed-modules =
        builtins.length (builtins.attrNames (engine.nodesByType result "module"));
        # → 8
    };
}
