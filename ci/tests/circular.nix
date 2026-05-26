{ lib, engine, ... }:
let
  inherit (engine) circular;

  roots = engine.buildNodes {
    parentGraph = engine.vertex "node";
    importGraph = engine.empty;
    decls = {
      node = { init-val = 0; target = 10; };
    };
    types = {};
  };

  # Converging: increment until reaching target
  convergingResult = engine.eval {
    inherit roots;
    attributes = {
      children = self: id: {};
      imports = self: id: [];
      counter = circular { init = 0; maxIter = 20; } (
        self: id: prev:
          let target = (self.node id).decls.target;
          in if prev >= target then prev else prev + 1
      );
    };
  };

  # Non-converging: always changes
  divergingRoots = engine.buildNodes {
    parentGraph = engine.vertex "div";
    importGraph = engine.empty;
    decls = { div = {}; };
    types = {};
  };

  divergingResult = engine.eval {
    roots = divergingRoots;
    attributes = {
      children = self: id: {};
      imports = self: id: [];
      forever = circular { init = 0; maxIter = 5; } (
        self: id: prev: prev + 1
      );
    };
  };

  # Custom equality
  customEqResult = engine.eval {
    inherit roots;
    attributes = {
      children = self: id: {};
      imports = self: id: [];
      approx = circular {
        init = 0.0;
        eq = a: b: (b - a) < 0.5;
        maxIter = 100;
      } (
        self: id: prev: prev + 0.3
      );
    };
  };
in
{
  "circular" = {
    test-converges-to-target = {
      expr = convergingResult.get "node" "counter";
      expected = 10;
    };

    test-diverge-throws = {
      expr = builtins.tryEval (divergingResult.get "div" "forever");
      expected = { success = false; value = false; };
    };

    test-custom-eq-converges = {
      # Starts at 0, increments by 0.3. Converges when diff < 0.5 (immediate since 0.3 < 0.5)
      expr = customEqResult.get "node" "approx";
      expected = 0.3;
    };
  };
}
