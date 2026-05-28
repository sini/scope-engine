{
  description = "Infrastructure schema demo — SQL query engine on gen-schema + gen-graph + gen-scope";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    gen-schema.url = "github:sini/gen-schema";
    gen-graph.url = "github:sini/gen-graph";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-select.url = "github:sini/gen-select";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      gen-scope,
      gen-schema,
      gen-graph,
      gen-algebra,
      gen-select,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
      genLib = gen-algebra { inherit lib; };
      selectLib = gen-select.lib;
      schemaLib = import "${gen-schema}/nix/lib" {
        inherit lib;
        inputs = {
          gen = genLib;
        };
      };
      graphLib = gen-graph { inherit lib; };
      sql = import ./lib {
        inherit
          lib
          engine
          schemaLib
          graphLib
          genLib
          selectLib
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
