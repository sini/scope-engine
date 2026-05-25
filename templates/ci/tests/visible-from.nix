{ lib, engine, ... }:
let
  resolveNodes = engine.buildNodes {
    importGraph = engine.edges [
      { from = "child"; to = "parent"; }
    ];
    decls = {
      parent = { x = 1; };
      child = { y = 2; };
    };
  };
  result = engine.eval {
    baseNodes = resolveNodes;
    attributes = { };
  };

  ambigNodes = engine.buildNodes {
    importGraph = engine.edges [
      { from = "consumer"; to = "providerA"; }
      { from = "consumer"; to = "providerB"; }
    ];
    decls = {
      providerA = { x = 1; };
      providerB = { x = 2; };
    };
  };
  ambigResult = engine.eval {
    baseNodes = ambigNodes;
    attributes = { };
  };
in
{
  visible-from = {
    test-resolves-from-import = {
      expr = engine.visibleFrom (n: n.decls.x or null) result "child";
      expected = 1;
    };

    test-resolves-local = {
      expr = engine.visibleFrom (n: n.decls.y or null) result "child";
      expected = 2;
    };

    test-no-match = {
      expr = engine.visibleFrom (n: n.decls.z or null) result "child";
      expected = null;
    };

    test-ambiguous-detects = {
      expr = engine.ambiguous { dataFilter = n: n.decls.x or null; } ambigResult "consumer";
      expected = true;
    };

    test-not-ambiguous = {
      expr = engine.ambiguous { dataFilter = n: n.decls.y or null; } result "child";
      expected = false;
    };
  };
}
