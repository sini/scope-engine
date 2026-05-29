{
  description = "nix-config ACL: unified access control with three-level scope graph resolution";
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      genScope = gen-scope { inherit lib; };
      groups = import ./data/groups.nix;
      environments = import ./data/environments.nix;
      hosts = import ./data/hosts.nix;
      inherit
        (import ./graph.nix {
          inherit
            genScope
            lib
            groups
            environments
            hosts
            ;
        })
        roots
        ;
      inherit (import ./attributes.nix { inherit genScope lib roots; }) attributes;
      result = genScope.eval { inherit roots attributes; };
      resolveOn = host: user: result.get "host:${host}" "resolveUser" user;
    in
    {
      tests = import ./tests.nix {
        inherit
          genScope
          lib
          result
          resolveOn
          ;
      };
    };
}
