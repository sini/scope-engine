{ lib, engine, ... }:
let
  parentGraph = engine.overlay (engine.edge "child" "parent") (engine.edge "grandchild" "child");

  baseNodes = engine.buildNodes {
    parentGraph = engine.overlay parentGraph (engine.vertex "sibling");
    importGraph = engine.edge "child" "sibling";
    decls = {
      parent = {
        color = "blue";
        size = "large";
      };
      child = {
        color = "green";
      };
      grandchild = { };
      sibling = {
        color = "red";
        tool = "hammer";
      };
    };
    types = {
      parent = "dept";
      child = "team";
      grandchild = "team";
      sibling = "team";
    };
  };

  attributes = { };

  result = engine.eval {
    inherit baseNodes attributes;
  };
in
{
  query-extras = {
    # queryAll — returns all reachable results (Neron 2015 §2.3)
    test-query-all-multiple-reachable = {
      expr =
        let
          # child has local color=green, import color=red, parent color=blue
          all = engine.queryAll {
            dataFilter = node: node.decls.color or null;
          } result "child";
        in
        builtins.sort builtins.lessThan all;
      expected = [
        "blue"
        "green"
        "red"
      ];
    };

    test-query-all-grandchild = {
      expr =
        let
          all = engine.queryAll {
            dataFilter = node: node.decls.color or null;
          } result "grandchild";
        in
        builtins.sort builtins.lessThan all;
      # grandchild has no local color, walks P to child (green + import red) then parent (blue)
      expected = [
        "blue"
        "green"
        "red"
      ];
    };

    test-query-all-i-only = {
      expr = engine.queryAll {
        dataFilter = node: node.decls.color or null;
        labelWF = "I";
      } result "child";
      # Local (green) + import (red), no parent walk
      expected = [
        "green"
        "red"
      ];
    };

    test-query-all-no-results = {
      expr = engine.queryAll {
        dataFilter = node: node.decls.nonexistent or null;
      } result "child";
      expected = [ ];
    };

    # collectByType
    test-collect-by-type = {
      expr =
        let
          teams = engine.collectByType "team" (self: id: [ id ]) result;
        in
        builtins.sort builtins.lessThan teams;
      expected = [
        "child"
        "grandchild"
        "sibling"
      ];
    };

    test-collect-by-type-single = {
      expr = engine.collectByType "dept" (self: id: [ id ]) result;
      expected = [ "parent" ];
    };

    test-collect-by-type-none = {
      expr = engine.collectByType "nonexistent" (self: id: [ id ]) result;
      expected = [ ];
    };

    # Seen-imports cycle prevention (Neron 2015 §2.4, Fig. 11)
    # Cyclic import: A imports B, B imports A. Without seen-tracking this diverges.
    test-seen-imports-cycle = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertices [
              "a"
              "b"
            ];
            importGraph = engine.overlay (engine.edge "a" "b") (engine.edge "b" "a");
            decls = {
              a = {
                val = "from-a";
              };
              b = {
                val = "from-b";
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        # a imports b, b imports a. query on a should find local val, not diverge.
        engine.query {
          dataFilter = node: node.decls.val or null;
        } r "a";
      expected = "from-a";
    };

    # Self-import: scope imports itself.
    test-seen-imports-self = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "x";
            importGraph = engine.edge "x" "x";
            decls = {
              x = {
                val = "self";
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        engine.query {
          dataFilter = node: node.decls.val or null;
        } r "x";
      expected = "self";
    };
  };
}
