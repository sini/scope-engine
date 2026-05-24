{
  description = "Infrastructure schema demo — SQL query engine on gen-schema + gen-graph + scope-engine";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    gen-schema.url = "github:sini/gen-schema";
    gen-graph.url = "github:sini/gen-graph";
    gen.url = "github:sini/gen";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      scope-engine,
      gen-schema,
      gen-graph,
      gen,
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
      graphLib = gen-graph {
        inherit lib;
        engine = engine;
      };
      sql = import ./lib {
        inherit
          lib
          engine
          schemaLib
          graphLib
          genLib
          ;
      };
    in
    {
      inherit sql;
      tests = import ./tests.nix {
        inherit
          lib
          engine
          sql
          schemaLib
          graphLib
          genLib
          ;
      };
    };
}
