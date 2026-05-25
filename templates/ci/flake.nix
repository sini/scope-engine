{
  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      gen-scope,
      nixpkgs,
      nix-unit,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      engine = gen-scope { inherit lib; };
      testFiles = lib.pipe (builtins.readDir ./tests) [
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n))
        builtins.attrNames
      ];
      tests = lib.foldl' (
        acc: file: acc // (import ./tests/${file} { inherit lib engine; })
      ) { } testFiles;
    in
    {
      inherit tests;
      checks = lib.genAttrs lib.systems.flakeExposed (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          assertTests = lib.mapAttrsToList (
            suite: subtests:
            lib.mapAttrsToList (
              name: t:
              if t.expr == t.expected then true
              else throw "FAIL ${suite}.${name}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
            ) subtests
          ) tests;
        in
        {
          default = pkgs.runCommand "gen-scope-tests" { } ''
            echo "${toString (builtins.length (lib.flatten assertTests))} tests passed"
            touch $out
          '';
        }
      );
      devShells = lib.genAttrs lib.systems.flakeExposed (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ nix-unit.packages.${system}.default ];
          };
        }
      );
    };
}
