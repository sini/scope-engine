{ lib, engine, ... }:
let
  baseNodes = engine.buildNodes {
    parentGraph = engine.edge "child" "parent";
    importGraph = engine.edge "child" "sibling";
    decls = {
      parent = {
        name = "from-parent";
      };
      child = {
        name = "from-child";
      };
      sibling = {
        name = "from-sibling";
      };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  ambiguity = {
    # Multiple reachable (local + import + parent) = ambiguous.
    test-ambiguous-true = {
      expr = engine.ambiguous {
        dataFilter = node: node.decls.name or null;
      } result "child";
      expected = true;
    };

    # Only one reachable = not ambiguous.
    test-ambiguous-false = {
      expr = engine.ambiguous {
        dataFilter = node: node.decls.name or null;
      } result "parent";
      expected = false;
    };

    # No results = not ambiguous.
    test-ambiguous-none = {
      expr = engine.ambiguous {
        dataFilter = node: node.decls.nonexistent or null;
      } result "child";
      expected = false;
    };

    # I-only: child has local + import = 2 reachable = ambiguous.
    test-ambiguous-i-only = {
      expr = engine.ambiguous {
        dataFilter = node: node.decls.name or null;
        labelWF = "I";
      } result "child";
      expected = true;
    };
  };
}
