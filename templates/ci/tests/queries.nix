{ lib, engine, ... }:
let
  inherit (engine) parent children childrenIds ancestors siblings descendants nodesByType;

  # Tree: root → {a, b}; a → {c}
  roots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "a" "root")
      (engine.edge "b" "root")
      (engine.edge "c" "a")
    ];
    importGraph = engine.empty;
    decls = {
      root = {};
      a = {};
      b = {};
      c = {};
    };
    types = { root = "env"; a = "host"; b = "host"; c = "user"; };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: [];
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };
in
{
  "queries" = {
    test-parent-of-child = {
      expr = parent result "a";
      expected = "root";
    };

    test-parent-of-root = {
      expr = parent result "root";
      expected = null;
    };

    test-children-of-root = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (children result "root"));
      expected = [ "a" "b" ];
    };

    test-children-of-leaf = {
      expr = builtins.attrNames (children result "c");
      expected = [];
    };

    test-childrenIds = {
      expr = builtins.sort builtins.lessThan (childrenIds result "root");
      expected = [ "a" "b" ];
    };

    test-ancestors-of-c = {
      expr = ancestors result "c";
      expected = [ "a" "root" ];
    };

    test-ancestors-of-root = {
      expr = ancestors result "root";
      expected = [];
    };

    test-siblings-of-a = {
      expr = siblings result "a";
      expected = [ "b" ];
    };

    test-siblings-of-root = {
      expr = siblings result "root";
      expected = [];
    };

    test-descendants-of-root = {
      expr = builtins.sort builtins.lessThan (descendants result "root");
      expected = [ "a" "b" "c" ];
    };

    test-descendants-of-a = {
      expr = descendants result "a";
      expected = [ "c" ];
    };

    test-descendants-of-leaf = {
      expr = descendants result "c";
      expected = [];
    };

    test-nodesByType-host = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (nodesByType result "host"));
      expected = [ "a" "b" ];
    };

    test-nodesByType-user = {
      expr = builtins.attrNames (nodesByType result "user");
      expected = [ "c" ];
    };

    test-nodesByType-missing = {
      expr = nodesByType result "nonexistent";
      expected = {};
    };
  };
}
