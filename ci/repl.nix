# gen-scope REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  genScope = import ./.. { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit genScope;
}
// genScope
