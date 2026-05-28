{ lib, engine, ... }:
let
  inherit (engine) collectionAttr;

  # Helper: standard attributes block for neron tests.
  # Every graph needs children, imports, and the neron-based vals attribute.
  mkAttrs = roots: {
    children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
    imports = self: id: (self.node id).decls.__edges.I or [ ];
    vals = collectionAttr {
      traverse = "neron";
      extract = self: id: (self.node id).decls.val or null;
    };
  };

  # --- Test 1: P-only chain (root → mid → leaf) ---
  pOnlyRoots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "leaf" "mid")
      (engine.edge "mid" "root")
    ];
    decls = {
      root.val = "root-val";
      mid.val = "mid-val";
      leaf.val = "leaf-val";
    };
    types = { };
  };
  pOnlyResult = engine.eval {
    roots = pOnlyRoots;
    attributes = mkAttrs pOnlyRoots;
    parseParent = id: (pOnlyRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 2: I-edge graph (leaf imports dep; leaf → root via P) ---
  iEdgeRoots = engine.buildNodes {
    parentGraph = engine.edge "leaf" "root";
    importGraph = engine.edge "leaf" "dep";
    decls = {
      root.val = "root-val";
      leaf.val = "leaf-val";
      dep.val = "dep-val";
    };
    types = { };
  };
  iEdgeResult = engine.eval {
    roots = iEdgeRoots;
    attributes = mkAttrs iEdgeRoots;
    parseParent = id: (iEdgeRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 3: Diamond dedup (leaf imports a and b; a also imports b) ---
  diamondRoots = engine.buildNodes {
    importGraph = engine.overlays [
      (engine.edge "leaf" "a")
      (engine.edge "leaf" "b")
      (engine.edge "a" "b")
    ];
    decls = {
      leaf.val = "leaf-val";
      a.val = "a-val";
      b.val = "b-val";
    };
    types = { };
  };
  diamondResult = engine.eval {
    roots = diamondRoots;
    attributes = mkAttrs diamondRoots;
    parseParent = id: (diamondRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 4: Parent has its own imports ---
  parentImportsRoots = engine.buildNodes {
    parentGraph = engine.edge "leaf" "root";
    importGraph = engine.overlays [
      (engine.edge "leaf" "leaf-dep")
      (engine.edge "root" "root-dep")
    ];
    decls = {
      leaf.val = "leaf-val";
      leaf-dep.val = "leaf-dep-val";
      root.val = "root-val";
      root-dep.val = "root-dep-val";
    };
    types = { };
  };
  parentImportsResult = engine.eval {
    roots = parentImportsRoots;
    attributes = mkAttrs parentImportsRoots;
    parseParent = id: (parentImportsRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 5: Root only (P-only chain queried at root) ---
  # Reuse pOnlyRoots/pOnlyResult, query at root

  # --- Test 6: Cycle — a imports b, b imports a, both children of root ---
  cycleRoots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "a" "root")
      (engine.edge "b" "root")
    ];
    importGraph = engine.overlays [
      (engine.edge "a" "b")
      (engine.edge "b" "a")
    ];
    decls = {
      root = {
        val = "root-val";
      };
      a = {
        val = "a-val";
      };
      b = {
        val = "b-val";
      };
    };
    types = { };
  };
  cycleResult = engine.eval {
    roots = cycleRoots;
    attributes = mkAttrs cycleRoots;
    parseParent = id: (cycleRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 7: Null skip — mid has no val field ---
  nullRoots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "leaf" "mid")
      (engine.edge "mid" "root")
    ];
    decls = {
      root = {
        val = "root-val";
      };
      mid = { };
      leaf = {
        val = "leaf-val";
      };
    };
    types = { };
  };
  nullResult = engine.eval {
    roots = nullRoots;
    attributes = mkAttrs nullRoots;
    parseParent = id: (nullRoots.${id} or { parent = null; }).parent;
  };
in
{
  flake.tests."neron-traverse" = {
    test-p-only-chain = {
      expr = pOnlyResult.get "leaf" "vals";
      expected = [
        "leaf-val"
        "mid-val"
        "root-val"
      ];
    };

    test-i-edge-graph = {
      expr = iEdgeResult.get "leaf" "vals";
      expected = [
        "leaf-val"
        "dep-val"
        "root-val"
      ];
    };

    test-diamond-dedup = {
      expr = diamondResult.get "leaf" "vals";
      expected = [
        "leaf-val"
        "a-val"
        "b-val"
      ];
    };

    test-parent-has-imports = {
      expr = parentImportsResult.get "leaf" "vals";
      expected = [
        "leaf-val"
        "leaf-dep-val"
        "root-val"
        "root-dep-val"
      ];
    };

    test-root-only = {
      expr = pOnlyResult.get "root" "vals";
      expected = [ "root-val" ];
    };

    test-cycle-safe = {
      expr = cycleResult.get "a" "vals";
      expected = [
        "a-val"
        "b-val"
        "root-val"
      ];
    };

    test-null-extraction-skipped = {
      expr = nullResult.get "leaf" "vals";
      expected = [
        "leaf-val"
        "root-val"
      ];
    };
  };
}
