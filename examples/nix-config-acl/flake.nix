{
  description = "nix-config ACL: unified access control with three-level scope graph resolution";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs = { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
      groups = import ./data/groups.nix;
      environments = import ./data/environments.nix;
      hosts = import ./data/hosts.nix;
      inherit (import ./graph.nix { inherit engine lib groups environments hosts; }) baseNodes;
      inherit (import ./attributes.nix { inherit engine lib; }) attributes;
      result = engine.eval { inherit baseNodes attributes; };
      resolveOn = host: user: result.evaluated."host:${host}".get "resolveUser" user;
    in {
      tests = import ./tests.nix { inherit engine lib result resolveOn; };
    };
}
