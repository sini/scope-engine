{
  description = "RBAC permission resolver: role hierarchies and resource access control via scope graphs";
  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs = { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };
      inherit (import ./graph.nix { inherit engine; }) baseNodes;
      inherit (import ./attributes.nix { inherit engine lib; }) rolePermissions attributes;
      result = engine.eval { inherit baseNodes attributes; };
    in {
      tests = import ./tests.nix { inherit engine lib result rolePermissions; };
    };
}
