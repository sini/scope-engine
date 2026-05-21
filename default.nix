{ lib }:
let
  graph = import ./lib/graph.nix;
  buildNodes = import ./lib/build-nodes.nix { inherit lib; };
  queries = import ./lib/queries.nix { inherit lib; };
  resolve = import ./lib/resolve.nix { inherit lib; };
  eval = import ./lib/eval.nix { inherit lib; };
in
graph // buildNodes // queries // resolve // eval
