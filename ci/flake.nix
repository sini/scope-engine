{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      engine = import ./.. { inherit lib; };
      testFiles = lib.pipe (builtins.readDir ./tests) [
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n))
        builtins.attrNames
      ];
      tests = lib.foldl' (
        acc: file: acc // (import ./tests/${file} { inherit lib engine; })
      ) { } testFiles;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = lib.systems.flakeExposed;

      flake.tests = tests;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
        inputs.flake-root.flakeModule
      ];

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          assertTests = lib.mapAttrsToList (
            suite: subtests:
            lib.mapAttrsToList (
              name: t:
              if t.expr == t.expected then
                true
              else
                throw "FAIL ${suite}.${name}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
            ) subtests
          ) tests;
        in
        {
          treefmt = {
            projectRootFile = ".git/config";
            flakeCheck = false;
            enableDefaultExcludes = true;
            settings.on-unmatched = "info";
            programs = {
              actionlint.enable = true;
              nixfmt.enable = true;
              mdformat = {
                enable = true;
                package = pkgs.mdformat.withPlugins (p: [
                  p.mdformat-beautysh
                  p.mdformat-footnote
                  p.mdformat-frontmatter
                  p.mdformat-gfm
                  p.mdformat-simple-breaks
                ]);
              };
            };
          };

          checks.default = pkgs.runCommand "gen-scope-tests" { } ''
            echo "${toString (builtins.length (lib.flatten assertTests))} tests passed"
            touch $out
          '';

          devshells.default = {
            packages = [
              inputs.nix-unit.packages.${system}.default
            ];

            env = [
              {
                name = "FLAKE_ROOT";
                eval = "$PRJ_ROOT";
              }
            ];

            commands = [
              {
                name = "ci";
                help = "Run all checks, or a specific test [ci] [ci suite.test]";
                command = ''
                  nix-unit \
                    --flake "$FLAKE_ROOT/ci#tests''${1:+.$1}" \
                    --gc-roots-dir "$FLAKE_ROOT/ci/.gcroots" "''${@:2}"
                '';
              }
              {
                name = "fmt";
                help = "Format all files";
                command = ''
                  cd "$FLAKE_ROOT/ci" && nix fmt
                '';
              }
              {
                name = "repl";
                help = "Interactive REPL with gen-scope loaded";
                command = ''
                  nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"
                '';
              }
            ];
          };
        };
    };
}
