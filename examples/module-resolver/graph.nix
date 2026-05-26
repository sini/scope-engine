# LM-inspired module system scope graph (Neron 2015 §2.1, §3, §4).
#
# Modules form a scope hierarchy via parent edges (lexical nesting).
# Imports create cross-scope visibility via import edges.
# Declarations are resolved through the scope graph using the
# resolution calculus with specificity D < I < P.
#
# program:
#   module Std {
#     module IO     { def print = "io.print"; def format = "io.format" }
#     module Math   { def sqrt = "math.sqrt"; def pi = 3 }
#     module String { import Math; def concat = "string.concat" }
#   }
#   module App {
#     import Std.String
#     def main = "app.main"
#     module Sub {
#       import Std.IO
#       def helper = "sub.helper"
#     }
#   }
#   module Cycle1 { import Cycle2 }
#   module Cycle2 { import Cycle1 }
{ engine }:
let
  # Parent edges encode lexical nesting.
  parentGraph = engine.overlays [
    (engine.star "root" [ "Std" "App" "Cycle1" "Cycle2" ])
    (engine.star "Std" [ "Std.IO" "Std.Math" "Std.String" ])
    (engine.edge "App.Sub" "App")
  ];

  # Import edges encode module imports.
  importGraph = engine.overlays [
    (engine.edge "Std.String" "Std.Math")
    (engine.edge "App" "Std.String")
    (engine.edge "App.Sub" "Std.IO")
    # Cyclic: Cycle1 ↔ Cycle2
    (engine.edge "Cycle1" "Cycle2")
    (engine.edge "Cycle2" "Cycle1")
  ];

  baseNodes = engine.buildNodes {
    inherit parentGraph importGraph;
    decls = {
      root = { };
      Std = { };
      "Std.IO" = { print = "io.print"; format = "io.format"; };
      "Std.Math" = { sqrt = "math.sqrt"; pi = 3; };
      "Std.String" = { concat = "string.concat"; };
      App = { main = "app.main"; };
      "App.Sub" = { helper = "sub.helper"; };
      Cycle1 = { val = "c1"; };
      Cycle2 = { val = "c2"; };
    };
    types = {
      root = "root";
      Std = "module"; "Std.IO" = "module"; "Std.Math" = "module"; "Std.String" = "module";
      App = "module"; "App.Sub" = "module";
      Cycle1 = "module"; Cycle2 = "module";
    };
  };
in
{
  inherit baseNodes;
}
