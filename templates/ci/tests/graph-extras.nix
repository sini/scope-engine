{ lib, engine, ... }:
{
  graph-extras = {
    # overlays (Mokhov 2017 §2.2)
    test-overlays-empty = {
      expr = engine.overlays [ ];
      expected = engine.empty;
    };

    test-overlays-multiple = {
      expr =
        let
          g = engine.overlays [
            (engine.vertex "a")
            (engine.vertex "b")
            (engine.edge "c" "d")
          ];
        in
        {
          vertices = builtins.sort builtins.lessThan g.vertices;
          edge-count = builtins.length g.edges;
        };
      expected = {
        vertices = [
          "a"
          "b"
          "c"
          "d"
        ];
        edge-count = 1;
      };
    };

    # edges (Mokhov 2017 §3.1)
    test-edges-empty = {
      expr = engine.edges [ ];
      expected = engine.empty;
    };

    test-edges-multiple = {
      expr =
        let
          g = engine.edges [
            {
              from = "a";
              to = "b";
            }
            {
              from = "b";
              to = "c";
            }
          ];
        in
        {
          # Vertex dedup deferred to buildNodes (algebraic idempotence).
          vertices = lib.unique (builtins.sort builtins.lessThan g.vertices);
          edge-count = builtins.length g.edges;
        };
      expected = {
        vertices = [
          "a"
          "b"
          "c"
        ];
        edge-count = 2;
      };
    };

    # path (Mokhov 2017 §5.1)
    test-path-empty = {
      expr = engine.path [ ];
      expected = engine.empty;
    };

    test-path-single = {
      expr = engine.path [ "a" ];
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    test-path-chain = {
      expr =
        let
          g = engine.path [
            "a"
            "b"
            "c"
            "d"
          ];
        in
        {
          # Vertex dedup deferred to buildNodes (algebraic idempotence).
          vertices = lib.unique (builtins.sort builtins.lessThan g.vertices);
          edges = builtins.sort (a: b: a.from < b.from) g.edges;
        };
      expected = {
        vertices = [
          "a"
          "b"
          "c"
          "d"
        ];
        edges = [
          {
            from = "a";
            to = "b";
          }
          {
            from = "b";
            to = "c";
          }
          {
            from = "c";
            to = "d";
          }
        ];
      };
    };

    # circuit (Mokhov 2017 §5.1)
    test-circuit-empty = {
      expr = engine.circuit [ ];
      expected = engine.empty;
    };

    test-circuit-triangle = {
      expr =
        let
          g = engine.circuit [
            "a"
            "b"
            "c"
          ];
        in
        {
          edge-count = builtins.length g.edges;
          has-back-edge = engine.hasEdge "c" "a" g;
        };
      expected = {
        edge-count = 3;
        has-back-edge = true;
      };
    };

    # transpose (Mokhov 2017 §5.2)
    test-transpose = {
      expr =
        let
          g = engine.transpose (engine.edge "a" "b");
        in
        g.edges;
      expected = [
        {
          from = "b";
          to = "a";
        }
      ];
    };

    test-transpose-preserves-vertices = {
      expr =
        let
          g = engine.transpose (engine.overlay (engine.edge "a" "b") (engine.vertex "c"));
        in
        builtins.sort builtins.lessThan g.vertices;
      expected = [
        "a"
        "b"
        "c"
      ];
    };

    # hasVertex / hasEdge (Mokhov 2017 §3.2)
    test-has-vertex-true = {
      expr = engine.hasVertex "a" (engine.vertex "a");
      expected = true;
    };

    test-has-vertex-false = {
      expr = engine.hasVertex "x" (engine.vertex "a");
      expected = false;
    };

    test-has-edge-true = {
      expr = engine.hasEdge "a" "b" (engine.edge "a" "b");
      expected = true;
    };

    test-has-edge-false = {
      expr = engine.hasEdge "b" "a" (engine.edge "a" "b");
      expected = false;
    };

    # removeVertex / removeEdge (Mokhov 2017 §5.4-5.5)
    test-remove-vertex = {
      expr =
        let
          g = engine.removeVertex "b" (engine.path [
            "a"
            "b"
            "c"
          ]);
        in
        {
          vertices = builtins.sort builtins.lessThan g.vertices;
          edges = g.edges;
        };
      expected = {
        vertices = [
          "a"
          "c"
        ];
        edges = [ ];
      };
    };

    test-remove-edge = {
      expr =
        let
          g = engine.removeEdge "a" "b" (engine.path [
            "a"
            "b"
            "c"
          ]);
        in
        {
          has-ab = engine.hasEdge "a" "b" g;
          has-bc = engine.hasEdge "b" "c" g;
        };
      expected = {
        has-ab = false;
        has-bc = true;
      };
    };
  };
}
