{
  description = "Feature flag evaluator: hierarchical flag resolution with rollout rules";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      genScope = gen-scope { inherit lib; };
      graph = import ./graph.nix { inherit genScope lib; };
      attributes = import ./attributes.nix { inherit genScope lib; };
      inherit (graph) roots;
      result = genScope.eval {
        inherit roots;
        attributes = graph.mkAttributes roots attributes;
      };
    in
    {
      tests = import ./tests.nix { inherit genScope lib result; };
    };
}
