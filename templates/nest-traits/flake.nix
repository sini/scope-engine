{
  description = "Nest traits model on gen-schema + gen-aspects + scope-engine";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    gen-schema.url = "github:sini/gen-schema";
    gen-aspects.url = "github:sini/gen-aspects";
    gen.url = "github:sini/gen";
    gen-graph.url = "github:sini/gen-graph";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      scope-engine,
      gen-schema,
      gen-aspects,
      gen,
      gen-graph,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      genLib = gen { inherit lib; };
      schemaLib = import "${gen-schema}/nix/lib" {
        inherit lib;
        inputs = {
          gen = genLib;
        };
      };
      aspects = gen-aspects { inherit lib; };
      graphLib = gen-graph {
        inherit lib;
        engine = engine;
      };
      nest = import ./lib {
        inherit
          lib
          engine
          schemaLib
          aspects
          genLib
          ;
      };
    in
    {
      inherit nest;
      tests = import ./tests.nix {
        inherit
          lib
          engine
          nest
          schemaLib
          aspects
          genLib
          graphLib
          ;
      };
    };
}
