{
  description = "Nest traits model on gen-schema + gen-aspects + gen-scope";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    gen-schema.url = "github:sini/gen-schema";
    gen-aspects.url = "github:sini/gen-aspects";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-graph.url = "github:sini/gen-graph";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      gen-scope,
      gen-schema,
      gen-aspects,
      gen-algebra,
      gen-graph,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      genScope = gen-scope { inherit lib; };
      genAlgebra = gen-algebra { inherit lib; };
      genSchema = import "${gen-schema}/nix/lib" {
        inherit lib;
        inputs = {
          gen = genAlgebra;
        };
      };
      aspects = gen-aspects { inherit lib; };
      genGraph = gen-graph { inherit lib; };
      nest = import ./lib {
        inherit
          lib
          genScope
          genSchema
          aspects
          genAlgebra
          ;
      };
    in
    {
      inherit nest;
      tests = import ./tests.nix {
        inherit
          lib
          genScope
          nest
          genSchema
          aspects
          genAlgebra
          genGraph
          ;
      };
    };
}
