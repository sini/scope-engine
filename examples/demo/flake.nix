{
  description = "gen-scope demo: algebraic graphs, scope resolution, HOAG evaluation";

  inputs = {
    gen-scope.url = "github:sini/gen-scope";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { gen-scope, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = gen-scope { inherit lib; };
    in
    {

      # ===================================================================
      # 1. ALGEBRAIC GRAPH CONSTRUCTION (Mokhov 2017)
      #
      # Four primitives -- empty, vertex, overlay, connect -- form an
      # algebra where overlay is a commutative idempotent monoid and
      # connect distributes over overlay (Mokhov 2017 §3.1).
      # ===================================================================

      # 1a. Core primitives
      graphPrimitives =
        let
          # Overlay: union of vertices and edges (commutative, associative, idempotent)
          g1 = engine.overlay (engine.vertex "a") (engine.vertex "b");
          # Connect: overlay + cross-product edges from left to right
          g2 = engine.connect (engine.vertex "a") (engine.vertex "b");
        in
        {
          overlay-vertices = g1.vertices; # [ "a" "b" ]
          overlay-edges = g1.edges; # [] -- no edges from overlay
          connect-edges = g2.edges; # [ { from = "a"; to = "b"; } ]
        };

      # 1b. Derived constructors (Mokhov 2017 §2.2, §5.1)
      graphDerived =
        let
          # star: fan-in from leaves to center
          s = engine.star "hub" [
            "spoke1"
            "spoke2"
            "spoke3"
          ];
          # path: sequential chain a -> b -> c -> d
          p = engine.path [
            "a"
            "b"
            "c"
            "d"
          ];
          # circuit: path + back-edge from last to first
          c = engine.circuit [
            "x"
            "y"
            "z"
          ];
          # clique: fully connected -- n vertices, n*(n-1)/2 edges
          k = engine.clique [
            "1"
            "2"
            "3"
          ];
          # tree: recursive { root, children } structure
          t = engine.tree {
            root = "ceo";
            children = [
              {
                root = "vp-eng";
                children = [
                  {
                    root = "team-lead";
                    children = [ ];
                  }
                ];
              }
              {
                root = "vp-sales";
                children = [ ];
              }
            ];
          };
          # forest: multiple trees
          f = engine.forest [
            {
              root = "tree-a";
              children = [
                {
                  root = "leaf-1";
                  children = [ ];
                }
              ];
            }
            {
              root = "tree-b";
              children = [
                {
                  root = "leaf-2";
                  children = [ ];
                }
              ];
            }
          ];
          # edges: bulk construction from list
          e = engine.edges [
            {
              from = "src";
              to = "mid";
            }
            {
              from = "mid";
              to = "dst";
            }
          ];
          # overlays: fold a list of graphs
          o = engine.overlays [
            (engine.vertex "isolated-1")
            (engine.vertex "isolated-2")
            (engine.edge "linked-a" "linked-b")
          ];
        in
        {
          star-edge-count = builtins.length s.edges; # 3
          path-has-chain = engine.hasEdge "b" "c" p; # true
          circuit-has-back = engine.hasEdge "z" "x" c; # true
          clique-edge-count = builtins.length k.edges; # 3
          tree-has-depth = engine.hasEdge "team-lead" "vp-eng" t; # true
          forest-independent = !(engine.hasEdge "tree-a" "tree-b" f); # true
          edges-count = builtins.length e.edges; # 2
          overlays-vertex-count = builtins.length (lib.unique o.vertices); # 4
        };

      # 1c. Transformations (Mokhov 2017 §5.2-5.5)
      graphTransformations =
        let
          g = engine.path [
            "a"
            "b"
            "c"
          ];
          # gmap: rename all vertices
          mapped = engine.gmap (v: "prefix-${v}") g;
          # transpose: flip all edges
          flipped = engine.transpose g;
          # induce: subgraph matching predicate
          filtered = engine.induce (v: v != "b") g;
          # removeVertex: drop a vertex and its edges
          removed = engine.removeVertex "b" g;
          # removeEdge: drop a single edge
          snipped = engine.removeEdge "a" "b" g;
        in
        {
          gmap-vertex = builtins.head mapped.vertices; # "prefix-a"
          transpose-reversed = engine.hasEdge "b" "a" flipped; # true
          induce-no-b = !(engine.hasVertex "b" filtered); # true
          remove-vertex-no-edges = filtered.edges == [ ]; # true (both edges touched b)
          remove-edge-keeps-bc = engine.hasEdge "b" "c" snipped; # true
          remove-edge-drops-ab = !(engine.hasEdge "a" "b" snipped); # true
        };

      # ===================================================================
      # 2. SCOPE GRAPH CONSTRUCTION (Neron 2015 §2, Mokhov 2017 §7)
      #
      # Scope graphs model name resolution. Parent (P) edges encode
      # lexical nesting, import (I) edges encode cross-scope visibility.
      # buildNodes constructs a flat indexed node map from algebraic graphs.
      # ===================================================================

      scopeGraphBasic =
        let
          # A university: faculties contain departments contain labs
          parentGraph = engine.overlays [
            (engine.star "university" [
              "faculty:cs"
              "faculty:math"
            ])
            (engine.star "faculty:cs" [
              "dept:pl"
              "dept:systems"
            ])
            (engine.edge "lab:types" "dept:pl")
          ];

          # PL department imports from math faculty (cross-scope visibility)
          importGraph = engine.edge "dept:pl" "faculty:math";

          nodes = engine.buildNodes {
            inherit parentGraph importGraph;
            decls = {
              university = {
                name = "TU Delft";
                country = "NL";
              };
              "faculty:cs" = {
                dean = "Prof. Visser";
              };
              "faculty:math" = {
                dean = "Prof. Mokhov";
                specialty = "algebra";
              };
              "dept:pl" = {
                focus = "scope graphs";
              };
              "dept:systems" = {
                focus = "networks";
              };
              "lab:types" = {
                head = "Dr. Neron";
              };
            };
            types = {
              university = "institution";
              "faculty:cs" = "faculty";
              "faculty:math" = "faculty";
              "dept:pl" = "department";
              "dept:systems" = "department";
              "lab:types" = "lab";
            };
          };
        in
        {
          # Parent edges create tree structure
          lab-parent = nodes."lab:types".parent; # "dept:pl"
          cs-children = builtins.sort builtins.lessThan (
            builtins.attrNames (lib.filterAttrs (_: n: n.parent == "faculty:cs") nodes)
          );
          # -> [ "dept:pl" "dept:systems" ]

          # Import edges stored in decls.__edges.I
          pl-imports = nodes."dept:pl".decls.__edges.I or [ ]; # [ "faculty:math" ]

          # Types tag nodes for typed queries
          lab-type = nodes."lab:types".type; # "lab"

          # Node fields
          pl-decls = builtins.removeAttrs nodes."dept:pl".decls [ "__edges" ]; # { focus = "scope graphs"; }
          pl-id = nodes."dept:pl".id; # "dept:pl"
        };

      # ===================================================================
      # 3. STRUCTURAL QUERIES (safe during HOAG synthesis)
      # ===================================================================

      structuralQueries =
        let
          parentGraph = engine.overlays [
            (engine.star "root" [
              "a"
              "b"
            ])
            (engine.star "a" [
              "a1"
              "a2"
            ])
            (engine.edge "a1x" "a1")
          ];
          nodes = engine.buildNodes {
            inherit parentGraph;
            types = {
              root = "org";
              a = "team";
              b = "team";
              a1 = "person";
              a2 = "person";
              a1x = "pet";
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: _id: [ ];
            };
          };
        in
        {
          parent = engine.parent result "a1"; # "a"
          children = builtins.attrNames (engine.children result "a"); # [ "a1" "a2" ]
          ancestors = engine.ancestors result "a1x"; # [ "a1" "a" "root" ]
          siblings = engine.siblings result "a1"; # [ "a2" ]
          descendants = builtins.sort builtins.lessThan (engine.descendants result "root");
          # -> [ "a" "a1" "a1x" "a2" "b" ]

          # Boolean predicates
          is-ancestor = engine.isAncestor result "root" "a1x"; # true
          is-not-ancestor = engine.isAncestor result "b" "a1x"; # false
          is-descendant = engine.isDescendant result "a1x" "root"; # true

          # Typed queries
          teams = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "team"));
          # -> [ "a" "b" ]
        };

      # ===================================================================
      # 4. NAME RESOLUTION (Neron 2015 §2.3-2.4, §5)
      #
      # Resolution follows specificity ordering D < I < P:
      # local declarations beat imports, imports beat parent scope.
      # Well-formedness P*.I* prevents parent-walking after imports.
      # ===================================================================

      nameResolution =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.overlay (engine.edge "inner" "outer") (engine.edge "deep" "inner");
            importGraph = engine.edge "inner" "lib";
            decls = {
              outer = {
                color = "blue";
                size = "large";
              };
              inner = {
                color = "green";
              }; # shadows outer's color
              deep = { };
              lib = {
                color = "red";
                tool = "hammer";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
            };
          };
        in
        {
          # shadow (Neron §5 Def. 1): inner keys suppress outer
          shadow-merge =
            engine.shadow
              {
                a = 1;
                b = 2;
              }
              {
                a = 99;
                c = 3;
              };
          # -> { a = 1; b = 2; c = 3; }

          # resolve: specificity ordering D < I < P
          resolve-local-wins = engine.resolve {
            local = "local";
            imported = "imported";
            inherited = "inherited";
          }; # -> "local"

          # query: generalized combinator (van Antwerpen §2.1)
          # inner has local color=green, import color=red, parent color=blue
          # D < I means local green wins
          query-inner-color = engine.query {
            dataFilter = n: n.decls.color or null;
          } result "inner"; # -> "green"

          # deep has no local color, no imports, walks parent to inner (green)
          query-deep-inherits = engine.query {
            dataFilter = n: n.decls.color or null;
          } result "deep"; # -> "green"

          # Import-only query: tool comes from import (lib has tool)
          query-import-tool = engine.query {
            dataFilter = n: n.decls.tool or null;
          } result "inner"; # -> "hammer"

          # inherit': walks parent chain (Neron §2.3)
          inherit-size = engine.inherit' {
            resolve = n: n.decls.size or null;
          } result "deep"; # -> "large" (deep -> inner -> outer)
        };

      # ===================================================================
      # 5. REACHABILITY AND AMBIGUITY (Neron 2015 §2.3, van Antwerpen 2018)
      # ===================================================================

      ambiguityDetection =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.edge "scope" "parent";
            importGraph = engine.edge "scope" "imported";
            decls = {
              parent = {
                name = "from-parent";
              };
              scope = {
                name = "from-local";
              };
              imported = {
                name = "from-import";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
            };
          };
        in
        {
          all-reachable = builtins.sort builtins.lessThan (
            engine.queryAll {
              dataFilter = n: n.decls.name or null;
            } result "scope"
          );

          is-ambiguous = engine.ambiguous {
            dataFilter = n: n.decls.name or null;
          } result "scope"; # -> true

          not-ambiguous = engine.ambiguous {
            dataFilter = n: n.decls.name or null;
          } result "parent"; # -> false
        };

      # ===================================================================
      # 6. VISIBILITY POLICIES (Neron 2015 §2.5, van Antwerpen 2018 §2.1)
      # ===================================================================

      visibilityPolicies =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "modA"
              "modB"
              "modC"
            ];
            importGraph = engine.overlay (engine.edge "modA" "modB") (engine.edge "modB" "modC");
            decls = {
              modA = {
                x = "local-A";
              };
              modB = {
                x = "from-B";
                y = "from-B";
              };
              modC = {
                y = "from-C";
                z = "deep-C";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
            };
          };
        in
        {
          non-transitive = engine.query {
            dataFilter = n: n.decls.z or null;
          } result "modA";

          transitive = engine.query {
            dataFilter = n: n.decls.z or null;
            transitiveImports = true;
          } result "modA";

          transitive-shadowing = engine.query {
            dataFilter = n: n.decls.y or null;
            transitiveImports = true;
          } result "modA";

          include-semantics = engine.query {
            dataFilter = n: n.decls.x or null;
            localShadowsImport = false;
          } result "modA";
        };

      # ===================================================================
      # 7. SEEN-IMPORTS: CYCLE PREVENTION (Neron 2015 §2.4, rule X)
      # ===================================================================

      seenImports =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "a"
              "b"
            ];
            importGraph = engine.overlay (engine.edge "a" "b") (engine.edge "b" "a");
            decls = {
              a = {
                val = "from-a";
              };
              b = {
                val = "from-b";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
            };
          };
        in
        {
          a-resolves = engine.query {
            dataFilter = n: n.decls.val or null;
          } result "a";

          b-resolves = engine.query {
            dataFilter = n: n.decls.val or null;
          } result "b";
        };

      # ===================================================================
      # 8. DEMAND-DRIVEN EVALUATION (Mokhov 2018, Sloane 2009/2010)
      # ===================================================================

      demandDrivenEval =
        let
          parentGraph = engine.overlays [
            (engine.star "company" [
              "eng"
              "sales"
            ])
            (engine.star "eng" [
              "platform"
              "frontend"
            ])
            (engine.edge "infra" "platform")
          ];
          nodes = engine.buildNodes {
            inherit parentGraph;
            decls = {
              company = {
                location = "SF";
                budget = 1000000;
              };
              eng = { };
              sales = {
                budget = 200000;
              };
              platform = {
                size = 8;
              };
              frontend = {
                size = 5;
              };
              infra = {
                size = 3;
              };
            };
          };

          attributes = {
            children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
            imports = _self: _id: [ ];

            # Inherited: flows top-down via parent chain (Knuth 1968)
            location = engine.inherit' {
              resolve = n: n.decls.location or null;
            };

            # Synthesized: rolls up bottom-up from children
            headcount =
              self: id:
              let
                node = self.node id;
                local = node.decls.size or 0;
                childIds = builtins.attrNames (self.get id "children");
                childTotal = lib.foldl' (acc: cid: acc + (self.get cid "headcount")) 0 childIds;
              in
              local + childTotal;

            # Parameterized attribute (Sloane 2010 §3)
            configFor = engine.paramAttr (
              self: id: param:
              let
                node = self.node id;
              in
              node.decls.${param}
                or (if node.parent != null then self.get node.parent "configFor" param else null)
            );
          };

          r = engine.eval {
            roots = nodes;
            inherit attributes;
          };
        in
        {
          # Inherited attribute: location flows from company to all descendants
          infra-location = r.get "infra" "location"; # -> "SF"
          platform-location = r.get "platform" "location"; # -> "SF"

          # Synthesized attribute: headcount aggregates bottom-up
          eng-headcount = r.get "eng" "headcount"; # -> 16 (8+5+3)
          company-headcount = r.get "company" "headcount"; # -> 16

          # Parameterized attribute: lookup by key
          infra-budget = r.get "infra" "configFor" "budget"; # -> 1000000
        };

      # ===================================================================
      # 9. HOAG: DYNAMIC NODE SYNTHESIS (Vogt 1989)
      # ===================================================================

      hoagSynthesis =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "dept:eng"
              "dept:sales"
              "dept:hr"
            ];
            decls = {
              "dept:eng" = {
                budget = 500000;
                headcount = 45;
              };
              "dept:sales" = {
                budget = 200000;
                headcount = 20;
              };
              "dept:hr" = {
                budget = 100000;
                headcount = 8;
              };
            };
            types = {
              "dept:eng" = "department";
              "dept:sales" = "department";
              "dept:hr" = "department";
            };
          };

          result = engine.eval {
            roots = nodes;
            attributes = {
              children =
                _self: id:
                let
                  staticChildren = lib.filterAttrs (_: n: n.parent == id) nodes;
                  # Synthesize audit nodes for departments over budget threshold
                  audit = lib.optionalAttrs (lib.hasPrefix "dept:" id && (nodes.${id}.decls.budget or 0) > 150000) {
                    "audit:${id}" = {
                      id = "audit:${id}";
                      type = "audit";
                      parent = id;
                      decls = {
                        reviewer = "finance";
                        threshold = 150000;
                      };
                    };
                  };
                in
                staticChildren // audit;
              imports = _self: _id: [ ];
            };
          };
        in
        {
          # Synthesized nodes exist for departments over threshold
          has-eng-audit = result.allNodes ? "audit:dept:eng"; # true (500k > 150k)
          has-sales-audit = result.allNodes ? "audit:dept:sales"; # true (200k > 150k)
          no-hr-audit = !(result.allNodes ? "audit:dept:hr"); # true (100k < 150k)

          # Synthesized node data
          audit-reviewer = (result.node "audit:dept:eng").decls.reviewer; # "finance"

          # Base nodes protected from overwrite (monotone-add invariant)
          eng-budget = (result.node "dept:eng").decls.budget; # 500000 (unchanged)

          # Typed query finds synthesized nodes
          audit-count = builtins.length (builtins.attrNames (engine.nodesByType result "audit")); # 2
        };

      # ===================================================================
      # 10. CIRCULAR ATTRIBUTES (Sloane 2010 §2.2, Magnusson & Hedin)
      # ===================================================================

      circularAttributes =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertex "system";
            decls = {
              system = {
                target-accuracy = 95;
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: _id: { };
              imports = _self: _id: [ ];
              accuracy = engine.circular { init = 0; } (
                self: id: prev:
                let
                  target = (self.node id).decls.target-accuracy;
                in
                if prev >= target then
                  prev
                else
                  let
                    next = prev + ((target - prev) * 30 / 100 + 1);
                  in
                  if next > target then target else next
              );
            };
          };
        in
        {
          converged = result.get "system" "accuracy"; # -> 95
        };

      # ===================================================================
      # 11. IMPORT-SCOPED COLLECTION (Neron 2015 §2.4, rule I)
      # ===================================================================

      importCollection =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "app"
              "utils"
              "math"
            ];
            importGraph = engine.overlay (engine.edge "app" "utils") (engine.edge "app" "math");
            decls = {
              app = { };
              utils = {
                exports = [
                  "format"
                  "validate"
                ];
              };
              math = {
                exports = [
                  "sum"
                  "avg"
                ];
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
              available-fns = engine.collectImports (self: importId: (self.node importId).decls.exports or [ ]);
            };
          };
        in
        {
          app-fns = result.get "app" "available-fns";
          # -> [ "format" "validate" "sum" "avg" ]
        };

      # ===================================================================
      # 12. STRUCTURAL SUBTYPING (van Antwerpen 2018 §2.3)
      # ===================================================================

      structuralSubtyping =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "point2d"
              "point3d"
              "color"
            ];
            decls = {
              point2d = {
                x = "num";
                y = "num";
              };
              point3d = {
                x = "num";
                y = "num";
                z = "num";
              };
              color = {
                r = "num";
                g = "num";
                b = "num";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: _id: [ ];
            };
          };
        in
        {
          is-subtype = engine.subtypeOf { } result "point2d" "point3d"; # true
          not-subtype = engine.subtypeOf { } result "point3d" "point2d"; # false
          different = engine.subtypeOf { } result "color" "point3d"; # false
          value-eq = engine.subtypeOf {
            eq =
              _k: a: b:
              a == b;
          } result "point2d" "point3d"; # true (x and y types match)
        };

      # ===================================================================
      # 13. CUSTOM EDGE LABELS (van Antwerpen 2018 §2.1)
      # ===================================================================

      customEdgeLabels =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "baseRecord"
              "extRecord"
              "classA"
              "classB"
            ];
            edgeGraphs = {
              # R = record field extension
              R = engine.edge "extRecord" "baseRecord";
              # E = class inheritance
              E = engine.edge "classB" "classA";
            };
            decls = {
              baseRecord = {
                z = "num";
              };
              extRecord = {
                x = "num";
                y = "num";
              };
              classA = {
                method-foo = "() -> void";
              };
              classB = {
                method-bar = "() -> int";
              };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: _id: [ ];
              "edges-R" = _self: id: (_self.node id).decls.__edges.R or [ ];
              "edges-E" = _self: id: (_self.node id).decls.__edges.E or [ ];
            };
          };
        in
        {
          # followEdge: get targets for a custom label
          record-extends = engine.followEdge "R" result "extRecord";
          # -> [ "baseRecord" ]

          # collectByLabel: gather data from custom-labeled edges
          inherited-methods = engine.collectByLabel "E" (
            self: id: builtins.attrNames (builtins.removeAttrs (self.node id).decls [ "__edges" ])
          ) result "classB";
          # -> [ "method-foo" ]

          # Edge data from decls.__edges
          all-edges = (result.node "extRecord").decls.__edges;
          # -> { R = [ "baseRecord" ]; }
        };

      # ===================================================================
      # 14. SCOPED RELATIONS (van Antwerpen 2018 §2.1)
      # ===================================================================

      scopedRelations =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.edge "inner" "outer";
            decls = {
              outer = {
                x = 42;
                __typeRel = {
                  x = "Int";
                  y = "String";
                };
                __docRel = {
                  x = "The x coordinate";
                };
              };
              inner = { };
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: _id: [ ];
            };
          };
        in
        {
          # Value namespace (via decls)
          value-x = engine.query {
            dataFilter = n: n.decls.x or null;
          } result "inner"; # -> 42

          # Type namespace (via decls.__typeRel)
          type-x = engine.query {
            dataFilter = n: (n.decls.__typeRel or { }).x or null;
          } result "inner"; # -> "Int"

          # Doc namespace
          doc-x = engine.query {
            dataFilter = n: (n.decls.__docRel or { }).x or null;
          } result "inner"; # -> "The x coordinate"

          # Direct decl access
          decl-via-node = (result.node "outer").decls.x; # -> 42
        };

      # ===================================================================
      # 15. EVAL DEBUG: CYCLE TRACING (spec Open Question #2/#5)
      # ===================================================================

      evalDebugDemo =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.vertices [
              "a"
              "b"
            ];
            importGraph = engine.overlay (engine.edge "a" "b") (engine.edge "b" "a");
          };

          # Intentionally cyclic: a.ping reads b.ping, b.ping reads a.ping
          result = engine.evalDebug {
            roots = nodes;
            attributes = {
              children = _self: _id: { };
              imports = _self: id: (_self.node id).decls.__edges.I or [ ];
              ping =
                self: id:
                let
                  other = builtins.head (self.get id "imports");
                in
                self.get other "ping";
            };
          };

          # Try to evaluate -- will throw with structured cycle trace
          tried = builtins.tryEval (result.get "a" "ping");
        in
        {
          # The cycle is caught with a structured error, not infinite recursion
          cycle-caught = !tried.success; # -> true
        };

      # ===================================================================
      # 16. GLOBAL COLLECTION AND TYPED QUERIES
      # ===================================================================

      globalCollection =
        let
          nodes = engine.buildNodes {
            parentGraph = engine.star "org" [
              "teamA"
              "teamB"
              "teamC"
            ];
            decls = {
              org = { };
              teamA = {
                size = 5;
              };
              teamB = {
                size = 8;
              };
              teamC = {
                size = 3;
              };
            };
            types = {
              org = "org";
              teamA = "team";
              teamB = "team";
              teamC = "team";
            };
          };
          result = engine.eval {
            roots = nodes;
            attributes = {
              children = _self: id: lib.filterAttrs (_: n: n.parent == id) nodes;
              imports = _self: _id: [ ];
            };
          };
        in
        {
          # collect: iterate all nodes (global -- use sparingly)
          all-sizes = builtins.sort builtins.lessThan (
            engine.collect { } (self: id: [ ((self.node id).decls.size or 0) ]) result
          ); # -> [ 0 3 5 8 ]

          # collectByType: filter by type tag
          team-sizes = builtins.sort builtins.lessThan (
            engine.collectByType "team" (self: id: [ (self.node id).decls.size ]) result
          ); # -> [ 3 5 8 ]
        };
    };
}
