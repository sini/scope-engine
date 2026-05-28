{
  description = "Config cascade resolver: hierarchical config override (.env/kustomize pattern)";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
      inherit (import ./graph.nix { inherit engine; }) baseNodes;
      attributes = import ./attributes.nix { inherit engine lib; };
      result = engine.eval { inherit baseNodes attributes; };
    in
    {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
