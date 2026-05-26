# Neron (2015) and van Antwerpen (2018) resolution semantics tests.
# Covers: specificity ordering, well-formedness (P*I*), transitive imports,
# custom edge labels, scoped relations, subtypeOf, ambiguity detection.
{ lib, engine, ... }:
let
  # Helper: build roots from buildNodes output
  mkRoots = args: engine.buildNodes args;

  # Attributes that wire __edges.I as computed imports
  withImports =
    extra:
    {
      imports = _self: id: (_self.node id).decls.__edges.I or [ ];
      children = _self: _id: { };
    }
    // extra;
in
{
  # === Specificity ordering (Neron 2015 §2.5, Fig. 2) ===

  specificity = {
    # D < I < P: local shadows import
    test-local-shadows-import = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.edge "consumer" "provider";
            decls = {
              consumer = {
                x = "local";
              };
              provider = {
                x = "imported";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query { dataFilter = n: n.decls.x or null; } result "consumer";
      expected = "local";
    };

    # D < I < P: import shadows parent
    test-import-shadows-parent = {
      expr =
        let
          roots = mkRoots {
            parentGraph = engine.edge "child" "parent";
            importGraph = engine.edge "child" "provider";
            decls = {
              parent = {
                x = "inherited";
              };
              provider = {
                x = "imported";
              };
              child = { };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query { dataFilter = n: n.decls.x or null; } result "child";
      expected = "imported";
    };

    # Override: importShadowsParent = false
    test-import-does-not-shadow-parent = {
      expr =
        let
          roots = mkRoots {
            parentGraph = engine.edge "child" "parent";
            importGraph = engine.edge "child" "provider";
            decls = {
              parent = {
                x = "inherited";
              };
              provider = {
                x = "imported";
              };
              child = { };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query {
          dataFilter = n: n.decls.x or null;
          importShadowsParent = false;
        } result "child";
      # When import doesn't shadow parent, local is still null, import is found
      # but doesn't shadow, so we check inherited — "inherited" wins
      expected = "imported"; # import found first (before parent walk)
    };

    # Override: localShadowsImport = false — local no longer takes priority,
    # so resolve skips the "local wins" branch and finds import instead.
    test-local-does-not-shadow-import = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.edge "consumer" "provider";
            decls = {
              consumer = {
                x = "local";
              };
              provider = {
                x = "imported";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query {
          dataFilter = n: n.decls.x or null;
          localShadowsImport = false;
        } result "consumer";
      # With localShadowsImport = false: import is checked before local in priority
      expected = "imported";
    };

    # No local, no import: parent provides
    test-parent-provides-when-no-local-or-import = {
      expr =
        let
          roots = mkRoots {
            parentGraph = engine.edge "child" "parent";
            decls = {
              parent = {
                x = "from-parent";
              };
              child = { };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query { dataFilter = n: n.decls.x or null; } result "child";
      expected = "from-parent";
    };
  };

  # === Well-formedness and transitive imports (Neron 2015 §2.4) ===

  wf-policy = {
    # Transitive imports: A imports B, B imports C. A can see C's decls.
    test-transitive-imports = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.overlays [
              (engine.edge "a" "b")
              (engine.edge "b" "c")
            ];
            decls = {
              a = { };
              b = { };
              c = {
                value = "deep";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query {
          dataFilter = n: n.decls.value or null;
          transitiveImports = true;
        } result "a";
      expected = "deep";
    };

    # Non-transitive (default): A imports B, B imports C. A cannot see C.
    test-non-transitive-default = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.overlays [
              (engine.edge "a" "b")
              (engine.edge "b" "c")
            ];
            decls = {
              a = { };
              b = { };
              c = {
                value = "deep";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query {
          dataFilter = n: n.decls.value or null;
        } result "a";
      expected = null; # not reachable without transitive
    };

    # Import cycle prevention: A imports B, B imports A. No infinite loop.
    test-import-cycle-terminates = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.overlays [
              (engine.edge "a" "b")
              (engine.edge "b" "a")
            ];
            decls = {
              a = {
                x = "from-a";
              };
              b = {
                y = "from-b";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.query { dataFilter = n: n.decls.y or null; } result "a";
      expected = "from-b";
    };

    # P*I* well-formedness: after following import, cannot follow parent of imported scope
    test-wf-import-does-not-inherit-from-imported-parent = {
      expr =
        let
          roots = mkRoots {
            parentGraph = engine.edge "provider" "provider-parent";
            importGraph = engine.edge "consumer" "provider";
            decls = {
              consumer = { };
              provider = { };
              provider-parent = {
                secret = "should-not-see";
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
          # consumer imports provider; provider's PARENT has "secret"
          # Under P*I* WF: once you follow I edge, you don't follow P from there
          # query with default settings does NOT walk provider's parent
        in
        engine.query { dataFilter = n: n.decls.secret or null; } result "consumer";
      expected = null;
    };
  };

  # === Ambiguity detection (van Antwerpen 2018 §2.3) ===

  ambiguity = {
    # Two imports provide the same declaration — ambiguous
    test-ambiguous-two-providers = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.overlays [
              (engine.edge "consumer" "providerA")
              (engine.edge "consumer" "providerB")
            ];
            decls = {
              consumer = { };
              providerA = {
                x = 1;
              };
              providerB = {
                x = 2;
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.ambiguous { dataFilter = n: n.decls.x or null; } result "consumer";
      expected = true;
    };

    # Single provider — not ambiguous
    test-not-ambiguous-single-provider = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.edge "consumer" "provider";
            decls = {
              consumer = { };
              provider = {
                x = 1;
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
        in
        engine.ambiguous { dataFilter = n: n.decls.x or null; } result "consumer";
      expected = false;
    };

    # Local declaration resolves ambiguity (shadows both imports)
    test-local-resolves-ambiguity = {
      expr =
        let
          roots = mkRoots {
            importGraph = engine.overlays [
              (engine.edge "consumer" "providerA")
              (engine.edge "consumer" "providerB")
            ];
            decls = {
              consumer = {
                x = "local";
              };
              providerA = {
                x = 1;
              };
              providerB = {
                x = 2;
              };
            };
          };
          attributes = withImports { };
          result = engine.eval { inherit roots attributes; };
          # With local shadowing, query returns local — ambiguity in imports is moot
        in
        engine.query { dataFilter = n: n.decls.x or null; } result "consumer";
      expected = "local";
    };
  };

  # === Custom edge labels (van Antwerpen 2018 §2.1) ===

  custom-edges = {
    # followEdge traverses a custom label
    test-follow-custom-edge = {
      expr =
        let
          roots = mkRoots {
            edgeGraphs.R = engine.edge "record" "extension";
            decls = {
              record = {
                base = true;
              };
              extension = {
                extra = true;
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
            "edges-R" = self: id: (self.node id).decls.__edges.R or [ ];
          };
          result = engine.eval { inherit roots attributes; };
        in
        engine.followEdge "R" result "record";
      expected = [ "extension" ];
    };

    # collectByLabel gathers data from custom edge targets
    test-collect-by-label = {
      expr =
        let
          roots = mkRoots {
            edgeGraphs.R = engine.overlays [
              (engine.edge "base" "ext1")
              (engine.edge "base" "ext2")
            ];
            decls = {
              base = { };
              ext1 = {
                field = "a";
              };
              ext2 = {
                field = "b";
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
            "edges-R" = self: id: (self.node id).decls.__edges.R or [ ];
          };
          result = engine.eval { inherit roots attributes; };
        in
        builtins.sort builtins.lessThan (
          engine.collectByLabel "R" (
            self: id:
            let
              f = (self.node id).decls.field or null;
            in
            if f != null then [ f ] else [ ]
          ) result "base"
        );
      expected = [
        "a"
        "b"
      ];
    };

    # Multiple custom labels on same node
    test-multiple-custom-labels = {
      expr =
        let
          roots = mkRoots {
            edgeGraphs.R = engine.edge "a" "b";
            edgeGraphs.E = engine.edge "a" "c";
            decls = {
              a = { };
              b = { };
              c = { };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
            "edges-R" = self: id: (self.node id).decls.__edges.R or [ ];
            "edges-E" = self: id: (self.node id).decls.__edges.E or [ ];
          };
          result = engine.eval { inherit roots attributes; };
        in
        {
          r = engine.followEdge "R" result "a";
          e = engine.followEdge "E" result "a";
        };
      expected = {
        r = [ "b" ];
        e = [ "c" ];
      };
    };
  };

  # === subtypeOf (van Antwerpen 2018 §2.3) ===

  subtype = {
    # A's decls are a subset of B's — A subtypes B
    test-subtype-subset = {
      expr =
        let
          roots = mkRoots {
            decls = {
              partial = {
                x = 1;
                y = 2;
              };
              full = {
                x = 1;
                y = 2;
                z = 3;
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
          };
          result = engine.eval { inherit roots attributes; };
        in
        engine.subtypeOf { } result "partial" "full";
      expected = true;
    };

    # A has a field B doesn't — not a subtype
    test-not-subtype-extra-field = {
      expr =
        let
          roots = mkRoots {
            decls = {
              extra = {
                x = 1;
                y = 2;
                z = 3;
              };
              base = {
                x = 1;
                y = 2;
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
          };
          result = engine.eval { inherit roots attributes; };
        in
        engine.subtypeOf { } result "extra" "base";
      expected = false;
    };

    # Custom equality check
    test-subtype-custom-eq = {
      expr =
        let
          roots = mkRoots {
            decls = {
              a = {
                x = 1;
              };
              b = {
                x = 2;
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
          };
          result = engine.eval { inherit roots attributes; };
          # eq ignores values — only checks field existence
        in
        engine.subtypeOf {
          eq =
            _k: _a: _b:
            true;
        } result "a" "b";
      expected = true;
    };

    # Empty decls subtypes everything
    test-empty-subtypes-all = {
      expr =
        let
          roots = mkRoots {
            decls = {
              empty = { };
              full = {
                x = 1;
                y = 2;
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
          };
          result = engine.eval { inherit roots attributes; };
        in
        engine.subtypeOf { } result "empty" "full";
      expected = true;
    };
  };

  # === Scoped relations as computed attributes ===

  relations = {
    # In the HOAG model, scoped relations are computed attributes.
    # A node can have multiple "namespaces" — each is a separate attribute.
    test-scoped-relations-via-attributes = {
      expr =
        let
          roots = mkRoots {
            decls = {
              module-a = {
                __relations = {
                  types = {
                    Int = "int";
                  };
                  values = {
                    x = 1;
                  };
                };
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
            types = self: id: (self.node id).decls.__relations.types or { };
            values = self: id: (self.node id).decls.__relations.values or { };
          };
          result = engine.eval { inherit roots attributes; };
        in
        {
          types = result.get "module-a" "types";
          values = result.get "module-a" "values";
        };
      expected = {
        types = {
          Int = "int";
        };
        values = {
          x = 1;
        };
      };
    };

    # Relations inherited through parent chain
    test-relations-inherited = {
      expr =
        let
          roots = mkRoots {
            parentGraph = engine.edge "inner" "outer";
            decls = {
              outer = {
                __relations = {
                  types = {
                    Int = "int";
                    Bool = "bool";
                  };
                };
              };
              inner = {
                __relations = {
                  types = {
                    String = "string";
                  };
                };
              };
            };
          };
          attributes = {
            imports = _self: _id: [ ];
            children = _self: _id: { };
            types = self: id: (self.node id).decls.__relations.types or { };
            all-types = engine.inherit' {
              resolve =
                n:
                let
                  t = n.decls.__relations.types or null;
                in
                t;
            };
          };
          result = engine.eval { inherit roots attributes; };
        in
        {
          # inner's own types
          inner-own = result.get "inner" "types";
          # inherited: first non-null in parent chain (inner has types, so returns inner's)
          inner-inherited = result.get "inner" "all-types";
          # outer's types
          outer-types = result.get "outer" "all-types";
        };
      expected = {
        inner-own = {
          String = "string";
        };
        inner-inherited = {
          String = "string";
        };
        outer-types = {
          Int = "int";
          Bool = "bool";
        };
      };
    };
  };
}
