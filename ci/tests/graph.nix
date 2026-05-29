{ lib, genScope, ... }:
{
  flake.tests."graph" = {
    test-empty = {
      expr = genScope.empty;
      expected = {
        vertices = [ ];
        edges = [ ];
      };
    };

    test-vertex = {
      expr = genScope.vertex "a";
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    test-edge = {
      expr = genScope.edge "a" "b";
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
      expr = (genScope.overlay (genScope.vertex "a") (genScope.vertex "b")).vertices;
      expected = [
        "a"
        "b"
      ];
    };

    test-overlay-edges = {
      expr = (genScope.overlay (genScope.edge "a" "b") (genScope.edge "c" "d")).edges;
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
      expr = (genScope.connect (genScope.vertex "a") (genScope.vertex "b")).edges;
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
          (genScope.connect
            (genScope.vertices [
              "a"
              "b"
            ])
            (
              genScope.vertices [
                "c"
                "d"
              ]
            )
          ).edges;
      expected = 4;
    };

    test-vertices = {
      expr =
        (genScope.vertices [
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
        (genScope.path [
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
      expr = genScope.path [ "a" ];
      expected = {
        vertices = [ "a" ];
        edges = [ ];
      };
    };

    test-path-empty = {
      expr = genScope.path [ ];
      expected = {
        vertices = [ ];
        edges = [ ];
      };
    };

    test-circuit = {
      expr =
        (genScope.circuit [
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
          (genScope.star "center" [
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
      expr = genScope.gmap (x: "${x}-mapped") (genScope.edge "a" "b");
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
      expr = genScope.induce (x: x != "b") (
        genScope.path [
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
      expr = (genScope.transpose (genScope.edge "a" "b")).edges;
      expected = [
        {
          from = "b";
          to = "a";
        }
      ];
    };

    test-overlays = {
      expr =
        (genScope.overlays [
          (genScope.vertex "a")
          (genScope.vertex "b")
          (genScope.vertex "c")
        ]).vertices;
      expected = [
        "a"
        "b"
        "c"
      ];
    };

    test-hasVertex-true = {
      expr = genScope.hasVertex "a" (genScope.edge "a" "b");
      expected = true;
    };

    test-hasVertex-false = {
      expr = genScope.hasVertex "c" (genScope.edge "a" "b");
      expected = false;
    };

    test-hasEdge-true = {
      expr = genScope.hasEdge "a" "b" (genScope.edge "a" "b");
      expected = true;
    };

    test-hasEdge-false = {
      expr = genScope.hasEdge "b" "a" (genScope.edge "a" "b");
      expected = false;
    };

    test-removeVertex = {
      expr = genScope.removeVertex "b" (
        genScope.path [
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
        (genScope.removeEdge "a" "b" (
          genScope.path [
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
