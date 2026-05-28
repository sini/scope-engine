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
      graph = import ./graph.nix { inherit engine lib; };
      attributes = import ./attributes.nix { inherit engine lib; };
      inherit (graph) roots;
      result = engine.eval {
        inherit roots;
        attributes = graph.mkAttributes roots attributes;
      };
    in
    {
      tests = import ./tests.nix {
        inherit
          engine
          lib
          result
          roots
          ;
        attributes = graph.mkAttributes roots attributes;
      };
    };
}
