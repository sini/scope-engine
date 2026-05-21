{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.star "root" [
    "a"
    "b"
  ]) (engine.edge "a1" "a");

  baseNodes = engine.buildNodes {
    inherit parentGraph;
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  queries = {
    test-parent = {
      expr = engine.parent result "a";
      expected = "root";
    };

    test-parent-root = {
      expr = engine.parent result "root";
      expected = null;
    };

    test-children-ids = {
      expr = builtins.sort builtins.lessThan (engine.childrenIds result "root");
      expected = [
        "a"
        "b"
      ];
    };

    test-children = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (engine.children result "root"));
      expected = [
        "a"
        "b"
      ];
    };

    test-ancestors = {
      expr = engine.ancestors result "a1";
      expected = [
        "a"
        "root"
      ];
    };

    test-ancestors-root = {
      expr = engine.ancestors result "root";
      expected = [ ];
    };

    test-siblings = {
      expr = engine.siblings result "a";
      expected = [ "b" ];
    };

    test-siblings-root = {
      expr = engine.siblings result "root";
      expected = [ ];
    };

    test-descendants = {
      expr = builtins.sort builtins.lessThan (engine.descendants result "root");
      expected = [
        "a"
        "a1"
        "b"
      ];
    };
  };
}
