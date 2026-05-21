{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.star "root" [
    "child1"
    "child2"
  ]) (engine.edge "grandchild" "child1");

  nodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      root = {
        name = "root";
      };
      child1 = {
        name = "c1";
      };
    };
    types = {
      root = "dept";
      child1 = "team";
    };
  };
in
{
  build-nodes = {
    test-all-vertices-present = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames nodes);
      expected = [
        "child1"
        "child2"
        "grandchild"
        "root"
      ];
    };

    test-parent-edge = {
      expr = nodes.child1.parent;
      expected = "root";
    };

    test-root-has-no-parent = {
      expr = nodes.root.parent;
      expected = null;
    };

    test-children-ids = {
      expr = builtins.sort builtins.lessThan nodes.root.childrenIds;
      expected = [
        "child1"
        "child2"
      ];
    };

    test-decls-present = {
      expr = nodes.child1.decls;
      expected = {
        name = "c1";
      };
    };

    test-decls-default-empty = {
      expr = nodes.child2.decls;
      expected = { };
    };

    test-type-assigned = {
      expr = nodes.child1.type;
      expected = "team";
    };

    test-type-default-null = {
      expr = nodes.child2.type;
      expected = null;
    };

    test-grandchild-parent = {
      expr = nodes.grandchild.parent;
      expected = "child1";
    };

    test-import-graph = {
      expr =
        let
          importGraph = engine.edge "child1" "child2";
          n = engine.buildNodes {
            inherit parentGraph importGraph;
          };
        in
        n.child1.imports;
      expected = [ "child2" ];
    };

    test-no-imports-default = {
      expr = nodes.root.imports;
      expected = [ ];
    };
  };
}
