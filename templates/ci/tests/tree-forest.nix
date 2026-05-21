{ lib, engine, ... }:
{
  tree-forest = {
    # tree: single node.
    test-tree-leaf = {
      expr =
        let
          g = engine.tree {
            root = "a";
            children = [ ];
          };
        in
        {
          vertices = g.vertices;
          edges = g.edges;
        };
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    # tree: one level.
    test-tree-star = {
      expr =
        let
          g = engine.tree {
            root = "r";
            children = [
              {
                root = "c1";
                children = [ ];
              }
              {
                root = "c2";
                children = [ ];
              }
            ];
          };
        in
        {
          vertices = builtins.sort builtins.lessThan (lib.unique g.vertices);
          edge-count = builtins.length g.edges;
          has-r-c1 = engine.hasEdge "c1" "r" g;
          has-r-c2 = engine.hasEdge "c2" "r" g;
        };
      expected = {
        vertices = [
          "c1"
          "c2"
          "r"
        ];
        edge-count = 2;
        has-r-c1 = true;
        has-r-c2 = true;
      };
    };

    # tree: two levels deep.
    test-tree-nested = {
      expr =
        let
          g = engine.tree {
            root = "1";
            children = [
              {
                root = "2";
                children = [ ];
              }
              {
                root = "3";
                children = [
                  {
                    root = "4";
                    children = [ ];
                  }
                  {
                    root = "5";
                    children = [ ];
                  }
                ];
              }
            ];
          };
        in
        {
          vertices = builtins.sort builtins.lessThan (lib.unique g.vertices);
          has-1-3 = engine.hasEdge "3" "1" g;
          has-3-4 = engine.hasEdge "4" "3" g;
          has-3-5 = engine.hasEdge "5" "3" g;
        };
      expected = {
        vertices = [
          "1"
          "2"
          "3"
          "4"
          "5"
        ];
        has-1-3 = true;
        has-3-4 = true;
        has-3-5 = true;
      };
    };

    # forest: multiple trees.
    test-forest = {
      expr =
        let
          g = engine.forest [
            {
              root = "a";
              children = [
                {
                  root = "b";
                  children = [ ];
                }
              ];
            }
            {
              root = "x";
              children = [
                {
                  root = "y";
                  children = [ ];
                }
              ];
            }
          ];
        in
        {
          vertices = builtins.sort builtins.lessThan (lib.unique g.vertices);
          has-a-b = engine.hasEdge "b" "a" g;
          has-x-y = engine.hasEdge "y" "x" g;
          # No cross-tree edges.
          has-a-y = engine.hasEdge "a" "y" g;
        };
      expected = {
        vertices = [
          "a"
          "b"
          "x"
          "y"
        ];
        has-a-b = true;
        has-x-y = true;
        has-a-y = false;
      };
    };
  };
}
