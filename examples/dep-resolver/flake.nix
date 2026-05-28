{
  description = "Dependency resolver: package resolution with version constraints and conflict detection";
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
      inherit (graph) baseNodes synthesize;
      result = engine.eval { inherit baseNodes attributes synthesize; };
    in
    {
      tests = import ./tests.nix {
        inherit
          engine
          lib
          result
          baseNodes
          attributes
          ;
      };
    };
}
