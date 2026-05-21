# Tests for exports that lacked direct CI coverage.
{ lib, engine, ... }:
let
  baseNodes = engine.buildNodes {
    parentGraph = engine.overlay
      (engine.star "root" [ "a" "b" "c" ])
      (engine.edge "a1" "a");
    decls = {
      root = { val = "root-val"; size = 100; };
      a = { val = "a-val"; size = 10; };
      b = { val = "b-val"; size = 20; };
      c = { val = "c-val"; size = 30; };
      a1 = { val = "a1-val"; size = 5; };
    };
    types = {
      root = "root"; a = "team"; b = "team"; c = "team"; a1 = "member";
    };
  };
  result = engine.eval {
    inherit baseNodes;
    attributes = {
      # paramAttr: lookup a specific decl key by parameter
      lookup = engine.paramAttr (
        self: id: key: self.nodes.${id}.decls.${key} or null
      );
    };
  };
in
{
  coverage-gaps = {
    # ─── paramAttr (Sloane 2010 §3) ───────────────────────────────

    test-param-attr-found = {
      expr = result.evaluated.a.get "lookup" "val";
      expected = "a-val";
    };

    test-param-attr-missing = {
      expr = result.evaluated.a.get "lookup" "nonexistent";
      expected = null;
    };

    test-param-attr-different-nodes = {
      expr = {
        a = result.evaluated.a.get "lookup" "size";
        b = result.evaluated.b.get "lookup" "size";
      };
      expected = { a = 10; b = 20; };
    };

    # ─── collect (global collection) ──────────────────────────────

    test-collect-all = {
      expr = builtins.sort builtins.lessThan (
        engine.collect { } (self: id: [ id ]) result
      );
      expected = [ "a" "a1" "b" "c" "root" ];
    };

    test-collect-filtered = {
      expr = builtins.sort builtins.lessThan (
        engine.collect { filter = n: (n.decls.size or 0) >= 20; }
          (self: id: [ self.nodes.${id}.decls.val ]) result
      );
      expected = [ "b-val" "c-val" "root-val" ];
    };

    test-collect-empty = {
      expr = engine.collect { filter = _: false; }
        (self: id: [ id ]) result;
      expected = [ ];
    };

    # ─── Neron 2015 Fig. 11: self-import with no local decls ─────
    # A module imports itself. The queried name is NOT in the module's
    # own decls but IS in the imported (self) scope. Without seen-imports,
    # this would loop. With seen-imports, the self-import is skipped
    # and the query returns null.

    test-neron-fig11-self-import-no-local = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "mod";
            importGraph = engine.edge "mod" "mod";
            decls = { mod = { }; };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in engine.query {
          dataFilter = node: node.decls.missing or null;
        } r "mod";
      expected = null;
    };

    # Parent provides the value when self-import is skipped.
    test-neron-fig11-parent-fallback = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.edge "mod" "root";
            importGraph = engine.edge "mod" "mod";
            decls = {
              root = { found = "from-parent"; };
              mod = { };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in engine.query {
          dataFilter = node: node.decls.found or null;
        } r "mod";
      expected = "from-parent";
    };

    # ─── inherit_ cycle detection ─────────────────────────────────
    # Malformed parent graph with a cycle. inherit_ should throw,
    # not hang.

    test-inherit-parent-cycle-throws = {
      expr =
        let
          # Manually construct nodes with a parent cycle (a→b→a).
          # buildNodes would normally prevent this via tree structure,
          # but we can construct it with two edges.
          n = engine.buildNodes {
            parentGraph = engine.overlay
              (engine.edge "a" "b")
              (engine.edge "b" "a");
          };
          r = engine.eval {
            baseNodes = n;
            attributes = {
              val = engine.inherit_ { resolve = node: node.decls.found or null; };
            };
          };
          tried = builtins.tryEval (r.evaluated.a.get "val");
        in tried.success;
      expected = false;
    };
  };
}
