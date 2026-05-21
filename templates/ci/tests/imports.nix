{ lib, engine, ... }:
let
  parentGraph = engine.vertices [
    "provider"
    "consumer"
  ];

  importGraph = engine.edge "consumer" "provider";

  baseNodes = engine.buildNodes {
    inherit parentGraph importGraph;
    decls = {
      provider = {
        shared-tools = [
          "terraform"
          "k8s"
        ];
      };
      consumer = { };
    };
  };

  attributes = {
    available-tools =
      engine.collectImports (self: importId: self.nodes.${importId}.decls.shared-tools or [ ]);
  };

  result = engine.eval {
    inherit baseNodes attributes;
  };
in
{
  imports = {
    test-collect-imports = {
      expr = result.evaluated.consumer.get "available-tools";
      expected = [
        "terraform"
        "k8s"
      ];
    };

    test-no-imports-empty = {
      expr = result.evaluated.provider.get "available-tools";
      expected = [ ];
    };

    test-multiple-imports = {
      expr =
        let
          ig = engine.overlay (engine.edge "c" "p1") (engine.edge "c" "p2");
          n = engine.buildNodes {
            parentGraph = engine.vertices [
              "p1"
              "p2"
              "c"
            ];
            importGraph = ig;
            decls = {
              p1 = {
                tools = [ "nix" ];
              };
              p2 = {
                tools = [ "docker" ];
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = {
              tools = engine.collectImports (self: iid: self.nodes.${iid}.decls.tools or [ ]);
            };
          };
        in
        r.evaluated.c.get "tools";
      expected = [
        "nix"
        "docker"
      ];
    };
  };
}
