{ lib, engine, ... }:
let
  inherit (engine) collectionAttr collectImports;

  # Tree: root → {a, b}; a imports b
  roots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "a" "root")
      (engine.edge "b" "root")
    ];
    importGraph = engine.edge "a" "b";
    decls = {
      root = {
        tags = [ "root-tag" ];
      };
      a = {
        tags = [ "a-tag" ];
      };
      b = {
        tags = [ "b-tag" ];
      };
    };
    types = { };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: (self.node id).decls.__edges.I or [ ];

      tags = self: id: (self.node id).decls.tags or [ ];

      # Collect tags from imports
      import-tags = collectionAttr {
        traverse = "imports";
        extract = self: id: (self.node id).decls.tags or [ ];
      };

      # Collect tags from children
      child-tags = collectionAttr {
        traverse = "children";
        extract = self: id: (self.node id).decls.tags or [ ];
      };

      # Collect tags from siblings
      sibling-tags = collectionAttr {
        traverse = "siblings";
        extract = self: id: (self.node id).decls.tags or [ ];
      };

      # Collect from ancestors
      ancestor-tags = collectionAttr {
        traverse = "ancestors";
        extract = self: id: (self.node id).decls.tags or [ ];
      };

      # Filtered collection
      filtered-child-tags = collectionAttr {
        traverse = "children";
        extract = self: id: (self.node id).decls.tags or [ ];
        filter = node: node.id != "b";
      };

      # collectImports convenience
      import-tags-simple = collectImports (self: id: (self.node id).decls.tags or [ ]);
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };
in
{
  flake.tests."collection-attr" = {
    test-traverse-imports = {
      expr = result.get "a" "import-tags";
      expected = [ "b-tag" ];
    };

    test-traverse-children = {
      expr = builtins.sort builtins.lessThan (result.get "root" "child-tags");
      expected = [
        "a-tag"
        "b-tag"
      ];
    };

    test-traverse-siblings = {
      expr = result.get "a" "sibling-tags";
      expected = [ "b-tag" ];
    };

    test-traverse-siblings-symmetric = {
      expr = result.get "b" "sibling-tags";
      expected = [ "a-tag" ];
    };

    test-traverse-ancestors = {
      expr = result.get "a" "ancestor-tags";
      expected = [ "root-tag" ];
    };

    test-traverse-ancestors-root-empty = {
      expr = result.get "root" "ancestor-tags";
      expected = [ ];
    };

    test-filtered-collection = {
      expr = result.get "root" "filtered-child-tags";
      expected = [ "a-tag" ];
    };

    test-collectImports-convenience = {
      expr = result.get "a" "import-tags-simple";
      expected = [ "b-tag" ];
    };

    test-no-imports-empty = {
      expr = result.get "b" "import-tags";
      expected = [ ];
    };

    test-traverse-children-leaf = {
      expr = result.get "a" "child-tags";
      expected = [ ];
    };
  };
}
