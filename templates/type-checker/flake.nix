{
  description = "Type checker: structural records and subtyping via scope graphs (van Antwerpen 2018)";

  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      graph = import ./graph.nix { inherit engine; };
      attributes = import ./attributes.nix { inherit engine lib; };
      result = engine.eval { inherit (graph) baseNodes synthesize; inherit attributes; };
    in
    {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
