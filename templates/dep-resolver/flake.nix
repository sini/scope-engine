{
  description = "Dependency resolver: package resolution with version constraints and conflict detection";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs = { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      graph = import ./graph.nix { inherit engine; };
      attributes = import ./attributes.nix { inherit engine lib; };
      inherit (graph) baseNodes synthesize;
      result = engine.eval { inherit baseNodes attributes synthesize; };
    in {
      tests = import ./tests.nix { inherit engine lib result baseNodes attributes; };
    };
}
