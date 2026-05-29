{ lib, genScope, ... }:
let
  # Basic build
  basic = genScope.buildNodes {
    parentGraph = genScope.edge "child" "parent";
    importGraph = genScope.edge "child" "lib";
    decls = {
      parent = {
        x = 1;
      };
      child = {
        y = 2;
      };
      lib = {
        z = 3;
      };
    };
    types = {
      parent = "host";
      child = "user";
      lib = "library";
    };
  };

  # No edges (vertices declared via parentGraph)
  noEdges = genScope.buildNodes {
    parentGraph = genScope.vertices [
      "a"
      "b"
    ];
    importGraph = genScope.empty;
    decls = {
      a = {
        val = 1;
      };
      b = {
        val = 2;
      };
    };
    types = {
      a = "x";
    };
  };

  # Multiple import edges
  multiImport = genScope.buildNodes {
    parentGraph = genScope.empty;
    importGraph = genScope.overlays [
      (genScope.edge "a" "b")
      (genScope.edge "a" "c")
    ];
    decls = {
      a = { };
      b = { };
      c = { };
    };
    types = { };
  };
in
{
  flake.tests."build-nodes" = {
    test-output-has-all-vertices = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames basic);
      expected = [
        "child"
        "lib"
        "parent"
      ];
    };

    test-node-shape-id = {
      expr = basic.parent.id;
      expected = "parent";
    };

    test-node-shape-type = {
      expr = basic.parent.type;
      expected = "host";
    };

    test-node-shape-parent = {
      expr = basic.child.parent;
      expected = "parent";
    };

    test-node-shape-null-parent = {
      expr = basic.parent.parent;
      expected = null;
    };

    test-node-decls-present = {
      expr = basic.parent.decls.x;
      expected = 1;
    };

    test-edges-I-populated = {
      expr = basic.child.decls.__edges.I;
      expected = [ "lib" ];
    };

    test-edges-I-empty-for-root = {
      expr = basic.parent.decls.__edges.I or [ ];
      expected = [ ];
    };

    test-type-null-when-unset = {
      expr = noEdges.b.type;
      expected = null;
    };

    test-no-parent-when-no-P-edge = {
      expr = noEdges.a.parent;
      expected = null;
    };

    test-multiple-imports = {
      expr = builtins.sort builtins.lessThan multiImport.a.decls.__edges.I;
      expected = [
        "b"
        "c"
      ];
    };

    test-multiple-parent-edges-strict-throws = {
      # strict=true (default): P partial function violation throws eagerly
      expr =
        !(builtins.tryEval (
          genScope.buildNodes {
            parentGraph = genScope.overlays [
              (genScope.edge "x" "a")
              (genScope.edge "x" "b")
            ];
          }
        )).success;
      expected = true;
    };

    test-multiple-parent-edges-lazy-deferred = {
      # strict=false: throws only when conflicting node's parent is accessed
      expr =
        let
          nodes = genScope.buildNodes {
            strict = false;
            parentGraph = genScope.overlays [
              (genScope.edge "x" "a")
              (genScope.edge "x" "b")
            ];
          };
        in
        (builtins.tryEval (builtins.attrNames nodes)).success;
      expected = true;
    };

    test-decls-default-empty = {
      expr = builtins.removeAttrs basic.lib.decls [ "__edges" ];
      expected = {
        z = 3;
      };
    };

    test-custom-edge-graphs =
      let
        custom = genScope.buildNodes {
          parentGraph = genScope.empty;
          importGraph = genScope.empty;
          edgeGraphs = {
            D = genScope.edge "a" "b";
          };
          decls = {
            a = { };
            b = { };
          };
          types = { };
        };
      in
      {
        expr = custom.a.decls.__edges.D;
        expected = [ "b" ];
      };
  };
}
