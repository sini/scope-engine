{ lib, engine, ... }:
{
  flake.tests."graph" = {
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

    test-overlay-vertices = {
      expr = (engine.overlay (engine.vertex "a") (engine.vertex "b")).vertices;
      expected = [
        "a"
        "b"
      ];
    };

    test-overlay-edges = {
      expr = (engine.overlay (engine.edge "a" "b") (engine.edge "c" "d")).edges;
      expected = [
        {
          from = "a";
          to = "b";
        }
        {
          from = "c";
          to = "d";
        }
      ];
    };

    test-connect-cross-product = {
      expr = (engine.connect (engine.vertex "a") (engine.vertex "b")).edges;
      expected = [
        {
          from = "a";
          to = "b";
        }
      ];
    };

    test-connect-multi = {
      expr =
        builtins.length
          (engine.connect
            (engine.vertices [
              "a"
              "b"
            ])
            (
              engine.vertices [
                "c"
                "d"
              ]
            )
          ).edges;
      expected = 4;
    };

    test-vertices = {
      expr =
        (engine.vertices [
          "x"
          "y"
          "z"
        ]).vertices;
      expected = [
        "x"
        "y"
        "z"
      ];
    };

    test-path = {
      expr =
        (engine.path [
          "a"
          "b"
          "c"
        ]).edges;
      expected = [
        {
          from = "a";
          to = "b";
        }
        {
          from = "b";
          to = "c";
        }
      ];
    };

    test-path-single = {
      expr = engine.path [ "a" ];
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    test-path-empty = {
      expr = engine.path [ ];
      expected = {
        vertices = [ ];
        edges = [ ];
      };
    };

    test-circuit = {
      expr =
        (engine.circuit [
          "a"
          "b"
          "c"
        ]).edges;
      expected = [
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
          to = "a";
        }
      ];
    };

    test-star = {
      expr =
        builtins.sort (a: b: a.from < b.from)
          (engine.star "center" [
            "l1"
            "l2"
          ]).edges;
      expected = [
        {
          from = "l1";
          to = "center";
        }
        {
          from = "l2";
          to = "center";
        }
      ];
    };

    test-gmap = {
      expr = engine.gmap (x: "${x}-mapped") (engine.edge "a" "b");
      expected = {
        vertices = [
          "a-mapped"
          "b-mapped"
        ];
        edges = [
          {
            from = "a-mapped";
            to = "b-mapped";
          }
        ];
      };
    };

    test-induce = {
      expr = engine.induce (x: x != "b") (
        engine.path [
          "a"
          "b"
          "c"
        ]
      );
      expected = {
        vertices = [
          "a"
          "c"
        ];
        edges = [ ];
      };
    };

    test-transpose = {
      expr = (engine.transpose (engine.edge "a" "b")).edges;
      expected = [
        {
          from = "b";
          to = "a";
        }
      ];
    };

    test-overlays = {
      expr =
        (engine.overlays [
          (engine.vertex "a")
          (engine.vertex "b")
          (engine.vertex "c")
        ]).vertices;
      expected = [
        "a"
        "b"
        "c"
      ];
    };

    test-hasVertex-true = {
      expr = engine.hasVertex "a" (engine.edge "a" "b");
      expected = true;
    };

    test-hasVertex-false = {
      expr = engine.hasVertex "c" (engine.edge "a" "b");
      expected = false;
    };

    test-hasEdge-true = {
      expr = engine.hasEdge "a" "b" (engine.edge "a" "b");
      expected = true;
    };

    test-hasEdge-false = {
      expr = engine.hasEdge "b" "a" (engine.edge "a" "b");
      expected = false;
    };

    test-removeVertex = {
      expr = engine.removeVertex "b" (
        engine.path [
          "a"
          "b"
          "c"
        ]
      );
      expected = {
        vertices = [
          "a"
          "c"
        ];
        edges = [ ];
      };
    };

    test-removeEdge = {
      expr =
        (engine.removeEdge "a" "b" (
          engine.path [
            "a"
            "b"
            "c"
          ]
        )).edges;
      expected = [
        {
          from = "b";
          to = "c";
        }
      ];
    };
  };
}
