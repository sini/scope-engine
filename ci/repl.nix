# gen-scope REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  engine = import ./.. { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit engine;
}
// engine
