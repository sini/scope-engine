{ lib, engine, ... }:
let
  inherit (engine) evalDebug;

  # Simple case: no cycles
  roots = engine.buildNodes {
    parentGraph = engine.vertex "a";
    importGraph = engine.empty;
    decls = {
      a = {
        val = 42;
      };
    };
    types = { };
  };

  debugResult = evalDebug {
    inherit roots;
    attributes = {
      children = self: id: { };
      imports = self: id: [ ];
      value = self: id: (self.node id).decls.val or 0;
    };
    parseParent = _: null;
  };

  # Cycle case: a.x depends on a.y depends on a.x
  cycleRoots = engine.buildNodes {
    parentGraph = engine.vertex "a";
    importGraph = engine.empty;
    decls = {
      a = { };
    };
    types = { };
  };

  cycleResult = evalDebug {
    roots = cycleRoots;
    attributes = {
      children = self: id: { };
      imports = self: id: [ ];
      x = self: id: self.get id "y";
      y = self: id: self.get id "x";
    };
    parseParent = _: null;
  };

  # Indirect cycle: a.p → b.q → a.p
  indirectRoots = engine.buildNodes {
    parentGraph = engine.vertices [
      "a"
      "b"
    ];
    importGraph = engine.empty;
    decls = {
      a = { };
      b = { };
    };
    types = { };
  };

  indirectResult = evalDebug {
    roots = indirectRoots;
    attributes = {
      children = self: id: { };
      imports = self: id: [ ];
      p = self: id: self.get "b" "q";
      q = self: id: self.get "a" "p";
    };
    parseParent = _: null;
  };
in
{
  "eval-debug" = {
    test-no-cycle-works = {
      expr = debugResult.get "a" "value";
      expected = 42;
    };

    test-direct-cycle-throws = {
      expr = builtins.tryEval (cycleResult.get "a" "x");
      expected = {
        success = false;
        value = false;
      };
    };

    test-indirect-cycle-throws = {
      expr = builtins.tryEval (indirectResult.get "a" "p");
      expected = {
        success = false;
        value = false;
      };
    };

    test-unknown-attr-throws = {
      expr = builtins.tryEval (debugResult.get "a" "nope");
      expected = {
        success = false;
        value = false;
      };
    };

    test-node-resolution = {
      expr = (debugResult.node "a").id;
      expected = "a";
    };
  };
}
