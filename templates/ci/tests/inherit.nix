{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.star "root" [
    "mid"
  ]) (engine.edge "leaf" "mid");

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      root = {
        location = "SF";
      };
      mid = { };
      leaf = { };
    };
  };

  attributes = {
    location =
      engine.inherit_ { resolve = node: node.decls.location or null; };
  };

  result = engine.eval {
    inherit baseNodes attributes;
  };
in
{
  inherit_ = {
    test-direct-decl = {
      expr = result.evaluated.root.get "location";
      expected = "SF";
    };

    test-inherit-one-level = {
      expr = result.evaluated.mid.get "location";
      expected = "SF";
    };

    test-inherit-two-levels = {
      expr = result.evaluated.leaf.get "location";
      expected = "SF";
    };

    test-inherit-no-parent-allows-parent = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "alone";
            decls = { };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = {
              val = engine.inherit_ { resolve = node: node.decls.val or null; };
            };
          };
        in
        r.evaluated.alone.get "val";
      expected = null;
    };

    test-inner-shadows-outer = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.edge "child" "parent";
            decls = {
              parent = {
                x = "outer";
              };
              child = {
                x = "inner";
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = {
              x = engine.inherit_ { resolve = node: node.decls.x or null; };
            };
          };
        in
        r.evaluated.child.get "x";
      expected = "inner";
    };
  };
}
