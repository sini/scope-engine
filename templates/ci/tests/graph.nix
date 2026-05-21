{ lib, engine, ... }:
{
  graph = {
    test-empty = {
      expr = engine.empty;
      expected = {
        vertices = [ ];
        edges = [ ];
      };
    };

    test-vertex = {
      expr = engine.vertex "a";
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    test-edge = {
      expr = engine.edge "a" "b";
      expected = {
        vertices = [
          "a"
          "b"
        ];
        edges = [
          {
            from = "a";
            to = "b";
          }
        ];
      };
    };

    test-overlay-commutative = {
      expr =
        let
          g1 = engine.vertex "a";
          g2 = engine.vertex "b";
          ab = engine.overlay g1 g2;
          ba = engine.overlay g2 g1;
        in
        {
          ab-vertices = builtins.sort builtins.lessThan ab.vertices;
          ba-vertices = builtins.sort builtins.lessThan ba.vertices;
        };
      expected = {
        ab-vertices = [
          "a"
          "b"
        ];
        ba-vertices = [
          "a"
          "b"
        ];
      };
    };

    test-star = {
      expr =
        let
          g = engine.star "root" [
            "c1"
            "c2"
          ];
        in
        {
          vertices = builtins.sort builtins.lessThan g.vertices;
          edge-count = builtins.length g.edges;
          edges = builtins.sort (a: b: a.from < b.from) g.edges;
        };
      expected = {
        vertices = [
          "c1"
          "c2"
          "root"
        ];
        edge-count = 2;
        edges = [
          {
            from = "c1";
            to = "root";
          }
          {
            from = "c2";
            to = "root";
          }
        ];
      };
    };

    test-vertices = {
      expr =
        let
          g = engine.vertices [
            "a"
            "b"
            "c"
          ];
        in
        builtins.sort builtins.lessThan g.vertices;
      expected = [
        "a"
        "b"
        "c"
      ];
    };

    test-connect-cross-product = {
      expr =
        let
          g = engine.connect (engine.vertices [
            "a"
            "b"
          ]) (engine.vertices [
            "x"
            "y"
          ]);
        in
        builtins.length g.edges;
      expected = 4;
    };

    test-clique = {
      expr =
        let
          g = engine.clique [
            "a"
            "b"
            "c"
          ];
        in
        builtins.length g.edges;
      # a->b, a->c, b->c = 3 edges from foldl' connect
      expected = 3;
    };

    test-gmap = {
      expr =
        let
          g = engine.gmap (x: "prefix-${x}") (engine.edge "a" "b");
        in
        {
          inherit (g) vertices edges;
        };
      expected = {
        vertices = [
          "prefix-a"
          "prefix-b"
        ];
        edges = [
          {
            from = "prefix-a";
            to = "prefix-b";
          }
        ];
      };
    };

    test-induce = {
      expr =
        let
          g = engine.overlay (engine.edge "a" "b") (engine.edge "b" "c");
          filtered = engine.induce (v: v != "c") g;
        in
        {
          # Algebraic idempotence: dedup deferred to buildNodes.
          vertices = lib.unique (builtins.sort builtins.lessThan filtered.vertices);
          edges = filtered.edges;
        };
      expected = {
        vertices = [
          "a"
          "b"
        ];
        edges = [
          {
            from = "a";
            to = "b";
          }
        ];
      };
    };
  };
}
