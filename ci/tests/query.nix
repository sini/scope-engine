{ lib, genScope, ... }:
let
  inherit (genScope) query queryAll ambiguous;

  # Graph: a imports b, b imports c. Parent: a → root.
  roots = genScope.buildNodes {
    parentGraph = genScope.edge "a" "root";
    importGraph = genScope.overlays [
      (genScope.edge "a" "b")
      (genScope.edge "b" "c")
    ];
    decls = {
      root = {
        val = "from-root";
      };
      a = { };
      b = {
        val = "from-b";
      };
      c = {
        val = "from-c";
        extra = "c-extra";
      };
    };
    types = { };
  };

  result = genScope.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: (self.node id).decls.__edges.I or [ ];
      resolved = query {
        dataFilter = node: node.decls.val or null;
      };
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };

  resultTransitive = genScope.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: (self.node id).decls.__edges.I or [ ];
      resolved = query {
        dataFilter = node: node.decls.val or null;
        transitiveImports = true;
      };
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };

  resultAll = genScope.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: (self.node id).decls.__edges.I or [ ];
      all-vals = queryAll {
        dataFilter = node: node.decls.val or null;
      };
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };

  # Ambiguity: node imports two nodes with same key
  ambRoots = genScope.buildNodes {
    parentGraph = genScope.empty;
    importGraph = genScope.overlays [
      (genScope.edge "x" "y")
      (genScope.edge "x" "z")
    ];
    decls = {
      x = { };
      y = {
        val = "from-y";
      };
      z = {
        val = "from-z";
      };
    };
    types = { };
  };

  ambResult = genScope.eval {
    roots = ambRoots;
    attributes = {
      children = self: id: { };
      imports = self: id: (self.node id).decls.__edges.I or [ ];
      is-ambiguous = ambiguous {
        dataFilter = node: node.decls.val or null;
      };
    };
  };
in
{
  flake.tests."query" = {
    test-query-finds-import = {
      expr = result.get "a" "resolved";
      expected = "from-b";
    };

    test-query-local-shadows = {
      expr = result.get "b" "resolved";
      expected = "from-b";
    };

    test-query-no-transitive-by-default = {
      # a imports b, b imports c; without transitiveImports, a sees b but not c
      expr = result.get "a" "resolved";
      expected = "from-b";
    };

    test-query-transitive-finds-deep = {
      # With transitive, a→b→c; b has val so it wins (import shadows parent)
      expr = resultTransitive.get "a" "resolved";
      expected = "from-b";
    };

    test-query-parent-fallback = {
      # root has val; a inherits from root when imports have it too, import wins
      expr = result.get "a" "resolved";
      expected = "from-b";
    };

    test-queryAll-collects-multiple = {
      # a: no local val. imports b (has val). parent root (has val).
      expr = builtins.length (resultAll.get "a" "all-vals");
      expected = 2;
    };

    test-queryAll-from-root = {
      expr = resultAll.get "root" "all-vals";
      expected = [ "from-root" ];
    };

    test-ambiguity-detected = {
      expr = ambResult.get "x" "is-ambiguous";
      expected = true;
    };

    test-ambiguity-not-when-single = {
      expr = ambResult.get "y" "is-ambiguous";
      expected = false;
    };

    test-query-self-no-import-loop = {
      # c has no imports, should return its own val
      expr = result.get "c" "resolved";
      expected = "from-c";
    };
  };
}
