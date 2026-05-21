{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.edge "child" "parent") (engine.edge "grandchild" "child");

  importGraph = engine.edge "child" "sibling";

  baseNodes = engine.buildNodes {
    parentGraph = engine.overlay parentGraph (engine.vertex "sibling");
    inherit importGraph;
    decls = {
      parent = {
        color = "blue";
      };
      child = { };
      grandchild = { };
      sibling = {
        color = "red";
        tool = "hammer";
      };
    };
  };

  attributes = {
    # Query with PI: imports beat parent.
    color-pi = engine.query {
      dataFilter = node: node.decls.color or null;
    };

    # Query with P only: no imports.
    color-p = engine.query {
      dataFilter = node: node.decls.color or null;
      labelWF = "P";
    };

    # Query with I only: no parent walk.
    color-i = engine.query {
      dataFilter = node: node.decls.color or null;
      labelWF = "I";
    };
  };

  result = engine.eval {
    inherit baseNodes attributes;
  };
in
{
  query = {
    test-query-pi-import-wins = {
      # child imports sibling (color=red), parent has color=blue.
      # Import beats parent in PI mode.
      expr = result.evaluated.child.get "color-pi";
      expected = "red";
    };

    test-query-p-only-parent = {
      # P mode ignores imports, walks to parent.
      expr = result.evaluated.child.get "color-p";
      expected = "blue";
    };

    test-query-i-only-import = {
      # I mode only checks imports.
      expr = result.evaluated.child.get "color-i";
      expected = "red";
    };

    test-query-i-no-imports-null = {
      # grandchild has no imports, I-only returns null.
      expr = result.evaluated.grandchild.get "color-i";
      expected = null;
    };

    test-query-pi-grandchild-inherits = {
      # grandchild has no decls, no imports, walks parent chain.
      expr = result.evaluated.grandchild.get "color-p";
      expected = "blue";
    };
  };
}
