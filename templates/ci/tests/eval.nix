{ lib, engine, ... }:
let
  # The department/team example from the spec.
  parentGraph = engine.overlay (engine.vertices [
    "dept:eng"
    "dept:sales"
  ]) (engine.overlay (engine.star "dept:eng" [
    "team:platform"
    "team:frontend"
  ]) (engine.edge "team:field" "dept:sales"));

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      "dept:eng" = {
        budget = 500000;
        location = "SF";
      };
      "dept:sales" = {
        budget = 200000;
        location = "NYC";
      };
      "team:platform" = {
        size = 8;
        focus = "infra";
      };
      "team:frontend" = {
        size = 5;
        focus = "ui";
      };
      "team:field" = {
        size = 12;
        focus = "enterprise";
      };
    };
  };

  attributes = {
    location = engine.inherit_ { resolve = node: node.decls.location or null; };

    headcount =
      self: id:
      let
        node = self.nodes.${id};
        local = node.decls.size or 0;
        childTotal = lib.foldl' (
          acc: cid: acc + (self.evaluated.${cid}.get "headcount")
        ) 0 node.childrenIds;
      in
      local + childTotal;
  };

  result = engine.eval {
    inherit baseNodes attributes;
  };
in
{
  eval = {
    test-location-inherited = {
      expr = result.evaluated."team:platform".get "location";
      expected = "SF";
    };

    test-location-direct = {
      expr = result.evaluated."dept:eng".get "location";
      expected = "SF";
    };

    test-headcount-leaf = {
      expr = result.evaluated."team:platform".get "headcount";
      expected = 8;
    };

    test-headcount-rolls-up = {
      expr = result.evaluated."dept:eng".get "headcount";
      expected = 13;
    };

    test-headcount-single-child = {
      expr = result.evaluated."dept:sales".get "headcount";
      expected = 12;
    };

    test-unknown-attribute-throws = {
      expr =
        let
          threw = builtins.tryEval (result.evaluated."dept:eng".get "nonexistent");
        in
        threw.success;
      expected = false;
    };
  };
}
