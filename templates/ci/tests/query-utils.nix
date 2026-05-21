{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.star "root" [
    "a"
    "b"
  ]) (engine.edge "a1" "a");

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    types = {
      root = "dept";
      a = "team";
      b = "team";
      a1 = "person";
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  query-utils = {
    # isAncestor
    test-is-ancestor-true = {
      expr = engine.isAncestor result "root" "a1";
      expected = true;
    };

    test-is-ancestor-direct = {
      expr = engine.isAncestor result "a" "a1";
      expected = true;
    };

    test-is-ancestor-false = {
      expr = engine.isAncestor result "b" "a1";
      expected = false;
    };

    test-is-ancestor-self = {
      expr = engine.isAncestor result "a" "a";
      expected = false;
    };

    # isDescendant
    test-is-descendant-true = {
      expr = engine.isDescendant result "a1" "root";
      expected = true;
    };

    test-is-descendant-false = {
      expr = engine.isDescendant result "a1" "b";
      expected = false;
    };

    # nodesByType
    test-nodes-by-type = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "team"));
      expected = [
        "a"
        "b"
      ];
    };

    test-nodes-by-type-single = {
      expr = builtins.attrNames (engine.nodesByType result "dept");
      expected = [ "root" ];
    };

    test-nodes-by-type-none = {
      expr = engine.nodesByType result "nonexistent";
      expected = { };
    };
  };
}
