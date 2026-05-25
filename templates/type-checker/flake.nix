{
  description = "Type checker: structural records and subtyping via scope graphs (van Antwerpen 2018)";

  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
      graph = import ./graph.nix { inherit engine; };
      attributes = import ./attributes.nix { inherit engine lib; };
      result = engine.eval { inherit (graph) baseNodes synthesize; inherit attributes; };
    in
    {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
