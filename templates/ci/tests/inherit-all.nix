{ engine, ... }:
let
  nodes = engine.buildNodes {
    parentGraph = engine.edges [
      { from = "child"; to = "mid"; }
      { from = "mid"; to = "root"; }
    ];
    decls = {
      root = { constraints = [ "no-debug" ]; };
      mid = { constraints = [ "no-logs" ]; };
      child = { constraints = [ "no-trace" ]; };
    };
  };
  result = engine.eval {
    baseNodes = nodes;
    attributes = {
      allConstraints = engine.inheritAll {
        extract = node: node.decls.constraints or null;
      };
    };
  };
in
{
  inherit-all = {
    test-accumulates-from-ancestors = {
      expr = result.evaluated.child.get "allConstraints";
      expected = [ "no-trace" "no-logs" "no-debug" ];
    };

    test-root-returns-local = {
      expr = result.evaluated.root.get "allConstraints";
      expected = [ "no-debug" ];
    };

    test-mid-gets-self-and-parent = {
      expr = result.evaluated.mid.get "allConstraints";
      expected = [ "no-logs" "no-debug" ];
    };

    test-no-decls-returns-empty = {
      expr =
        let
          emptyNodes = engine.buildNodes {
            parentGraph = engine.edges [
              { from = "leaf"; to = "top"; }
            ];
          };
          r = engine.eval {
            baseNodes = emptyNodes;
            attributes = {
              gathered = engine.inheritAll {
                extract = node: node.decls.x or null;
              };
            };
          };
        in
        r.evaluated.leaf.get "gathered";
      expected = [ ];
    };
  };
}
