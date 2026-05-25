{ engine, ... }:
let
  nodes = engine.buildNodes {
    importGraph = engine.edges [
      {
        from = "a";
        to = "b";
      }
      {
        from = "a";
        to = "c";
      }
    ];
    parentGraph = engine.edges [
      {
        from = "b";
        to = "root";
      }
      {
        from = "c";
        to = "root";
      }
      {
        from = "a";
        to = "root";
      }
    ];
    decls = {
      b = {
        tags = [ "web" ];
      };
      c = {
        tags = [
          "api"
          "db"
        ];
      };
      root = {
        tags = [ "infra" ];
      };
    };
  };
  result = engine.eval {
    baseNodes = nodes;
    attributes = {
      importedTags = engine.collectionAttr {
        traverse = "imports";
        extract = self: id: self.nodes.${id}.decls.tags or null;
      };
      childTags = engine.collectionAttr {
        traverse = "children";
        extract = self: id: self.nodes.${id}.decls.tags or null;
      };
      siblingTags = engine.collectionAttr {
        traverse = "siblings";
        extract = self: id: self.nodes.${id}.decls.tags or null;
      };
      ancestorTags = engine.collectionAttr {
        traverse = "ancestors";
        extract = self: id: self.nodes.${id}.decls.tags or null;
      };
      filteredTags = engine.collectionAttr {
        traverse = "imports";
        extract = self: id: self.nodes.${id}.decls.tags or null;
        filter = node: node.decls ? tags && builtins.length node.decls.tags > 1;
      };
    };
  };
in
{
  collection-attr.test-collect-from-imports = {
    expr = builtins.sort builtins.lessThan (result.evaluated.a.get "importedTags");
    expected = [
      "api"
      "db"
      "web"
    ];
  };

  collection-attr.test-collect-from-children = {
    expr = builtins.sort builtins.lessThan (result.evaluated.root.get "childTags");
    expected = [
      "api"
      "db"
      "web"
    ];
  };

  collection-attr.test-collect-from-siblings = {
    expr = builtins.sort builtins.lessThan (result.evaluated.b.get "siblingTags");
    expected = [
      "api"
      "db"
    ];
  };

  collection-attr.test-collect-from-ancestors = {
    expr = result.evaluated.a.get "ancestorTags";
    expected = [ "infra" ];
  };

  collection-attr.test-filter-prunes = {
    expr = builtins.sort builtins.lessThan (result.evaluated.a.get "filteredTags");
    expected = [
      "api"
      "db"
    ];
  };

  collection-attr.test-empty-imports = {
    expr = result.evaluated.c.get "importedTags";
    expected = [ ];
  };
}
