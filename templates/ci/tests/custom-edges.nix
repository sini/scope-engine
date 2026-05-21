{ lib, engine, ... }:
let
  # van Antwerpen 2018 §2.1: custom edge labels beyond P/I.
  # Model record extension (R) and class inheritance (E) edges.
  #
  # Record: { x: num, y: num } extends { z: num }
  # Class: class D extends C

  baseNodes = engine.buildNodes {
    parentGraph = engine.vertices [
      "rec-base"
      "rec-ext"
      "classC"
      "classD"
      "classE"
    ];
    edgeGraphs = {
      # R = record field edge (van Antwerpen Fig. 4)
      R = engine.edge "rec-ext" "rec-base";
      # E = extension/inheritance edge
      E = engine.overlay (engine.edge "classD" "classC") (engine.edge "classE" "classD");
    };
    decls = {
      "rec-base" = {
        z = "num";
      };
      "rec-ext" = {
        x = "num";
        y = "num";
      };
      classC = {
        fieldF = 42;
      };
      classD = {
        fieldG = 99;
      };
      classE = {
        fieldF = 100;
        fieldH = 77;
      };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  custom-edges = {
    # edgesByLabel is populated for custom labels.
    test-edges-by-label-R = {
      expr = result.nodes."rec-ext".edgesByLabel.R;
      expected = [ "rec-base" ];
    };

    test-edges-by-label-E = {
      expr = result.nodes.classD.edgesByLabel.E;
      expected = [ "classC" ];
    };

    test-edges-by-label-empty = {
      expr = result.nodes."rec-base".edgesByLabel.R or [ ];
      expected = [ ];
    };

    # followEdge works with custom labels.
    test-follow-edge-R = {
      expr = engine.followEdge "R" result "rec-ext";
      expected = [ "rec-base" ];
    };

    test-follow-edge-E-chain = {
      expr = engine.followEdge "E" result "classE";
      expected = [ "classD" ];
    };

    # collectByLabel: gather fields from record extension.
    test-collect-record-fields = {
      expr =
        let
          fields = engine.collectByLabel "R" (
            self: targetId: builtins.attrNames self.nodes.${targetId}.decls
          ) result "rec-ext";
        in
        builtins.sort builtins.lessThan fields;
      expected = [ "z" ];
    };

    # Inheritance chain: collect all inherited fields via E edges.
    test-collect-inherited = {
      expr =
        let
          # Recursive: follow E edges transitively.
          allInherited =
            self: id:
            let
              directParents = engine.followEdge "E" self id;
              directFields = lib.concatMap (
                pid: builtins.attrNames self.nodes.${pid}.decls
              ) directParents;
              transitiveFields = lib.concatMap (allInherited self) directParents;
            in
            directFields ++ transitiveFields;
          fields = allInherited result "classE";
        in
        builtins.sort builtins.lessThan (lib.unique fields);
      expected = [
        "fieldF"
        "fieldG"
      ];
    };

    # P and I still work alongside custom labels.
    test-backwards-compat = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.edge "child" "parent";
            importGraph = engine.edge "child" "provider";
            edgeGraphs = {
              X = engine.edge "child" "extra";
            };
            decls = {
              parent = {
                a = 1;
              };
              child = { };
              provider = {
                b = 2;
              };
              extra = {
                c = 3;
              };
            };
          };
        in
        {
          parent = n.child.parent;
          imports = n.child.imports;
          custom = n.child.edgesByLabel.X;
          has-P = n.child.edgesByLabel ? P;
          has-I = n.child.edgesByLabel ? I;
        };
      expected = {
        parent = "parent";
        imports = [ "provider" ];
        custom = [ "extra" ];
        has-P = true;
        has-I = true;
      };
    };
  };
}
