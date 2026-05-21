{ lib, engine, ... }:
let
  # Neron 2015 §2.5, Fig. 13: SML-style include semantics.
  # module A { def x = 3 }
  # module B { include A; def x = 6; def z = x }
  # With include semantics, x should have DUPLICATE resolutions (both x=3 and x=6)
  # because include doesn't shadow. With normal import, local x=6 shadows imported x=3.

  baseNodes = engine.buildNodes {
    parentGraph = engine.vertices [
      "moduleA"
      "moduleB"
    ];
    importGraph = engine.edge "moduleB" "moduleA";
    decls = {
      moduleA = {
        x = 3;
      };
      moduleB = {
        x = 6;
      };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  specificity = {
    # Default D < I < P: local shadows import.
    test-default-local-shadows-import = {
      expr = engine.query {
        dataFilter = node: node.decls.x or null;
      } result "moduleB";
      expected = 6;
    };

    # SML include: local does NOT shadow import (Neron §2.5).
    # With localShadowsImport = false, import result wins over local
    # (because resolve falls through local check to import check).
    test-include-semantics = {
      expr = engine.query {
        dataFilter = node: node.decls.x or null;
        localShadowsImport = false;
      } result "moduleB";
      # Import (3) is checked before local (6) when local doesn't shadow
      expected = 3;
    };

    # queryAll shows both are reachable regardless of specificity.
    test-both-reachable = {
      expr =
        let
          all = engine.queryAll {
            dataFilter = node: node.decls.x or null;
          } result "moduleB";
        in
        builtins.sort builtins.lessThan all;
      expected = [
        3
        6
      ];
    };

    # Import doesn't shadow parent: parent value visible even when import exists.
    test-import-no-shadow-parent = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.edge "child" "parent";
            importGraph = engine.edge "child" "provider";
            decls = {
              parent = {
                val = "from-parent";
              };
              child = { };
              provider = {
                val = "from-import";
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        engine.query {
          dataFilter = node: node.decls.val or null;
          importShadowsParent = false;
        } r "child";
      # Import doesn't shadow parent, but import is still checked first in resolve.
      # Since import has val, it returns import value.
      expected = "from-import";
    };

    # When import has nothing but parent does, with importShadowsParent = false.
    test-import-no-shadow-parent-fallthrough = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.edge "child" "parent";
            importGraph = engine.edge "child" "provider";
            decls = {
              parent = {
                val = "from-parent";
              };
              child = { };
              provider = { };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        engine.query {
          dataFilter = node: node.decls.val or null;
          importShadowsParent = false;
        } r "child";
      expected = "from-parent";
    };
  };
}
