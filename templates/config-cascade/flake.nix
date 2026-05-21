{
  description = "Config cascade resolver: hierarchical config override (.env/kustomize pattern)";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs = { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      inherit (import ./graph.nix { inherit engine; }) baseNodes;
      attributes = import ./attributes.nix { inherit engine lib; };
      result = engine.eval { inherit baseNodes attributes; };
    in {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
