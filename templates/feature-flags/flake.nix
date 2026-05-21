{
  description = "Feature flag evaluator: hierarchical flag resolution with rollout rules";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs = { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      graph = import ./graph.nix { inherit engine lib; };
      attributes = import ./attributes.nix { inherit engine lib; };
      inherit (graph) baseNodes synthesize;
      result = engine.eval { inherit baseNodes attributes synthesize; };
    in {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
