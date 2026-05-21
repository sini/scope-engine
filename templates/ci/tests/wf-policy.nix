{ lib, engine, ... }:
let
  # Neron 2015 §2.4, Fig. 7: transitive imports.
  # module A { import B; def a = b + c }
  # module B { import C; def b = 0 }
  # module C { def c = 0; def b = 1 }
  # With transitive imports: A can reach C's declarations through B's import of C.
  # Without transitive imports: A only sees B's direct declarations.

  baseNodes = engine.buildNodes {
    parentGraph = engine.vertices [
      "modA"
      "modB"
      "modC"
    ];
    importGraph = engine.overlay (engine.edge "modA" "modB") (engine.edge "modB" "modC");
    decls = {
      modA = { };
      modB = {
        val-b = "from-B";
      };
      modC = {
        val-c = "from-C";
        val-b = "from-C-shadowed";
      };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  wf-policy = {
    # Default (non-transitive): A only sees B's decls, not C's.
    test-non-transitive-import = {
      expr = engine.query {
        dataFilter = node: node.decls.val-c or null;
      } result "modA";
      expected = null;
    };

    test-non-transitive-sees-direct = {
      expr = engine.query {
        dataFilter = node: node.decls.val-b or null;
      } result "modA";
      expected = "from-B";
    };

    # Transitive: A sees through B into C.
    test-transitive-import = {
      expr = engine.query {
        dataFilter = node: node.decls.val-c or null;
        transitiveImports = true;
      } result "modA";
      expected = "from-C";
    };

    # Transitive with shadowing: B's val-b shadows C's val-b.
    test-transitive-import-shadowing = {
      expr = engine.query {
        dataFilter = node: node.decls.val-b or null;
        transitiveImports = true;
      } result "modA";
      # B's val-b is found first (direct import), so it wins
      expected = "from-B";
    };

    # Transitive with queryAll shows both val-b values reachable.
    test-transitive-query-all = {
      expr =
        let
          all = engine.queryAll {
            dataFilter = node: node.decls.val-b or null;
            transitiveImports = true;
          } result "modA";
        in
        builtins.sort builtins.lessThan all;
      expected = [
        "from-B"
        "from-C-shadowed"
      ];
    };

    # Three-level transitive chain: A → B → C, C has unique decl.
    test-transitive-three-levels = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertices [
              "x"
              "y"
              "z"
            ];
            importGraph = engine.overlay (engine.edge "x" "y") (engine.edge "y" "z");
            decls = {
              x = { };
              y = { };
              z = {
                deep = "found";
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        engine.query {
          dataFilter = node: node.decls.deep or null;
          transitiveImports = true;
        } r "x";
      expected = "found";
    };
  };
}
