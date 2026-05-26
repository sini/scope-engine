{ lib, engine, ... }:
let
  inherit (engine)
    shadow
    resolve
    inherit'
    inheritAll
    ;
in
{
  "resolve" = {
    test-shadow-inner-wins = {
      expr =
        shadow
          {
            a = 1;
            b = 2;
          }
          {
            a = 99;
            c = 3;
          };
      expected = {
        a = 1;
        b = 2;
        c = 3;
      };
    };

    test-shadow-disjoint = {
      expr = shadow { x = 1; } { y = 2; };
      expected = {
        x = 1;
        y = 2;
      };
    };

    test-shadow-identical = {
      expr = shadow { a = 1; } { a = 1; };
      expected = {
        a = 1;
      };
    };

    test-shadow-empty-inner = {
      expr = shadow { } { a = 1; };
      expected = {
        a = 1;
      };
    };

    test-shadow-empty-outer = {
      expr = shadow { a = 1; } { };
      expected = {
        a = 1;
      };
    };

    test-resolve-local-wins = {
      expr = resolve {
        local = "L";
        imported = "I";
        inherited = "P";
      };
      expected = "L";
    };

    test-resolve-imported-wins-over-inherited = {
      expr = resolve {
        local = null;
        imported = "I";
        inherited = "P";
      };
      expected = "I";
    };

    test-resolve-inherited-fallback = {
      expr = resolve {
        local = null;
        imported = null;
        inherited = "P";
      };
      expected = "P";
    };

    test-resolve-all-null = {
      expr = resolve {
        local = null;
        imported = null;
        inherited = null;
      };
      expected = null;
    };

    test-resolve-specificity-override = {
      expr = resolve {
        local = null;
        imported = "I";
        inherited = "P";
        localShadowsImport = false;
        importShadowsParent = false;
      };
      expected = "I";
    };

    test-inherit-walks-parent =
      let
        roots = engine.buildNodes {
          parentGraph = engine.edge "child" "parent";
          importGraph = engine.empty;
          decls = {
            parent = {
              val = "found";
            };
            child = { };
          };
          types = { };
        };
        result = engine.eval {
          inherit roots;
          attributes = {
            children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
            imports = self: id: [ ];
            resolved-val = inherit' {
              resolve = node: node.decls.val or null;
            };
          };
          parseParent = id: (roots.${id} or { parent = null; }).parent;
        };
      in
      {
        expr = result.get "child" "resolved-val";
        expected = "found";
      };

    test-inherit-stops-at-first =
      let
        roots = engine.buildNodes {
          parentGraph = engine.overlays [
            (engine.edge "c" "b")
            (engine.edge "b" "a")
          ];
          importGraph = engine.empty;
          decls = {
            a = {
              val = "root";
            };
            b = {
              val = "mid";
            };
            c = { };
          };
          types = { };
        };
        result = engine.eval {
          inherit roots;
          attributes = {
            children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
            imports = self: id: [ ];
            resolved-val = inherit' {
              resolve = node: node.decls.val or null;
            };
          };
          parseParent = id: (roots.${id} or { parent = null; }).parent;
        };
      in
      {
        expr = result.get "c" "resolved-val";
        expected = "mid";
      };

    test-inheritAll-accumulates =
      let
        roots = engine.buildNodes {
          parentGraph = engine.overlays [
            (engine.edge "c" "b")
            (engine.edge "b" "a")
          ];
          importGraph = engine.empty;
          decls = {
            a = {
              tags = [ "root" ];
            };
            b = {
              tags = [ "mid" ];
            };
            c = {
              tags = [ "leaf" ];
            };
          };
          types = { };
        };
        result = engine.eval {
          inherit roots;
          attributes = {
            children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
            imports = self: id: [ ];
            all-tags = inheritAll {
              extract = node: node.decls.tags or null;
            };
          };
          parseParent = id: (roots.${id} or { parent = null; }).parent;
        };
      in
      {
        expr = result.get "c" "all-tags";
        expected = [
          "leaf"
          "mid"
          "root"
        ];
      };
  };
}
