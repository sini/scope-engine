{ lib, genScope, ... }:
let
  inherit (genScope) collectionAttr;

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
  pOnlyRoots = genScope.buildNodes {
    parentGraph = genScope.overlays [
      (genScope.edge "leaf" "mid")
      (genScope.edge "mid" "root")
    ];
    decls = {
      root.val = "root-val";
      mid.val = "mid-val";
      leaf.val = "leaf-val";
    };
    types = { };
  };
  pOnlyResult = genScope.eval {
    roots = pOnlyRoots;
    attributes = mkAttrs pOnlyRoots;
    parseParent = id: (pOnlyRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 2: I-edge graph (leaf imports dep; leaf → root via P) ---
  iEdgeRoots = genScope.buildNodes {
    parentGraph = genScope.edge "leaf" "root";
    importGraph = genScope.edge "leaf" "dep";
    decls = {
      root.val = "root-val";
      leaf.val = "leaf-val";
      dep.val = "dep-val";
    };
    types = { };
  };
  iEdgeResult = genScope.eval {
    roots = iEdgeRoots;
    attributes = mkAttrs iEdgeRoots;
    parseParent = id: (iEdgeRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 3: Diamond dedup (leaf imports a and b; a also imports b) ---
  diamondRoots = genScope.buildNodes {
    importGraph = genScope.overlays [
      (genScope.edge "leaf" "a")
      (genScope.edge "leaf" "b")
      (genScope.edge "a" "b")
    ];
    decls = {
      leaf.val = "leaf-val";
      a.val = "a-val";
      b.val = "b-val";
    };
    types = { };
  };
  diamondResult = genScope.eval {
    roots = diamondRoots;
    attributes = mkAttrs diamondRoots;
    parseParent = id: (diamondRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 4: Parent has its own imports ---
  parentImportsRoots = genScope.buildNodes {
    parentGraph = genScope.edge "leaf" "root";
    importGraph = genScope.overlays [
      (genScope.edge "leaf" "leaf-dep")
      (genScope.edge "root" "root-dep")
    ];
    decls = {
      leaf.val = "leaf-val";
      leaf-dep.val = "leaf-dep-val";
      root.val = "root-val";
      root-dep.val = "root-dep-val";
    };
    types = { };
  };
  parentImportsResult = genScope.eval {
    roots = parentImportsRoots;
    attributes = mkAttrs parentImportsRoots;
    parseParent = id: (parentImportsRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 5: Root only (P-only chain queried at root) ---
  # Reuse pOnlyRoots/pOnlyResult, query at root

  # --- Test 6: Cycle — a imports b, b imports a, both children of root ---
  cycleRoots = genScope.buildNodes {
    parentGraph = genScope.overlays [
      (genScope.edge "a" "root")
      (genScope.edge "b" "root")
    ];
    importGraph = genScope.overlays [
      (genScope.edge "a" "b")
      (genScope.edge "b" "a")
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
  cycleResult = genScope.eval {
    roots = cycleRoots;
    attributes = mkAttrs cycleRoots;
    parseParent = id: (cycleRoots.${id} or { parent = null; }).parent;
  };

  # --- Test 7: Null skip — mid has no val field ---
  nullRoots = genScope.buildNodes {
    parentGraph = genScope.overlays [
      (genScope.edge "leaf" "mid")
      (genScope.edge "mid" "root")
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
  nullResult = genScope.eval {
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
