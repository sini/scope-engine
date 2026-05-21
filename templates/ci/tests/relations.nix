{ lib, engine, ... }:
let
  # van Antwerpen 2018 §2.1: scoped relations.
  # A scope can have multiple named relations, not just "decls".
  # E.g., type declarations vs value declarations in separate namespaces.

  baseNodes = engine.buildNodes {
    parentGraph = engine.edge "inner" "outer";
    decls = {
      outer = {
        x = "value-x";
      };
      inner = {
        y = "value-y";
      };
    };
    relations = {
      outer = {
        typeDecl = {
          x = "type-X";
          t = "type-T";
        };
      };
      inner = {
        typeDecl = {
          y = "type-Y";
        };
      };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  relations = {
    # Default decls relation still works.
    test-decls-unchanged = {
      expr = result.nodes.outer.decls;
      expected = {
        x = "value-x";
      };
    };

    # rels contains the ":" relation (from decls) + named relations.
    test-rels-contains-decls = {
      expr = result.nodes.outer.rels.":";
      expected = {
        x = "value-x";
      };
    };

    test-rels-contains-named = {
      expr = result.nodes.outer.rels.typeDecl;
      expected = {
        x = "type-X";
        t = "type-T";
      };
    };

    # Query via rels for type namespace.
    test-query-type-relation = {
      expr = engine.query {
        dataFilter = node: node.rels.typeDecl.x or null;
      } result "inner";
      # inner has no typeDecl.x, walks to outer which has type-X.
      expected = "type-X";
    };

    # Query via rels for value namespace.
    test-query-value-relation = {
      expr = engine.query {
        dataFilter = node: node.decls.x or null;
      } result "inner";
      # inner has no decls.x, walks to outer which has value-x.
      expected = "value-x";
    };

    # Same name in different relations — independent namespaces.
    test-independent-namespaces = {
      expr = {
        type = engine.query {
          dataFilter = node: node.rels.typeDecl.x or null;
        } result "outer";
        value = engine.query {
          dataFilter = node: node.decls.x or null;
        } result "outer";
      };
      expected = {
        type = "type-X";
        value = "value-x";
      };
    };

    # Node without relations gets empty rels.
    test-no-relations-empty = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "solo";
          };
        in
        n.solo.rels;
      expected = { };
    };
  };
}
