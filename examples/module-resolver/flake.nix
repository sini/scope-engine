{
  description = "Module resolver: Neron 2015 LM-style module system with scope graphs";

  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
      inherit (import ./graph.nix { inherit engine lib; }) roots;
      attributes = import ./attributes.nix { inherit engine lib roots; };
      result = engine.eval { inherit roots attributes; };
    in
    {
      tests = import ./tests.nix { inherit engine lib result; };
    };
}
