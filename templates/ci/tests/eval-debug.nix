{ lib, engine, ... }:
let
  # Basic test: evalDebug produces same results as eval for non-cyclic graphs.
  parentGraph = engine.overlay (engine.vertices [
    "dept:eng"
    "dept:sales"
  ]) (engine.overlay (engine.star "dept:eng" [
    "team:platform"
    "team:frontend"
  ]) (engine.edge "team:field" "dept:sales"));

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      "dept:eng" = {
        budget = 500000;
        location = "SF";
      };
      "dept:sales" = {
        budget = 200000;
        location = "NYC";
      };
      "team:platform" = {
        size = 8;
      };
      "team:frontend" = {
        size = 5;
      };
      "team:field" = {
        size = 12;
      };
    };
  };

  attributes = {
    location = engine.inherit' { resolve = node: node.decls.location or null; };
    headcount =
      self: id:
      let
        node = self.nodes.${id};
        local = node.decls.size or 0;
        childTotal = lib.foldl' (
          acc: cid: acc + (self.evaluated.${cid}.get "headcount")
        ) 0 node.childrenIds;
      in
      local + childTotal;
  };

  result = engine.evalDebug {
    inherit baseNodes attributes;
  };
in
{
  eval-debug = {
    # Same results as eval for non-cyclic evaluation.
    test-location-inherited = {
      expr = result.evaluated."team:platform".get "location";
      expected = "SF";
    };

    test-headcount-rolls-up = {
      expr = result.evaluated."dept:eng".get "headcount";
      expected = 13;
    };

    test-headcount-leaf = {
      expr = result.evaluated."team:field".get "headcount";
      expected = 12;
    };

    # Unknown attribute still throws.
    test-unknown-attribute = {
      expr =
        let
          tried = builtins.tryEval (result.evaluated."dept:eng".get "nonexistent");
        in
        tried.success;
      expected = false;
    };

    # Cycle detection: mutual reference between two nodes.
    test-cycle-detected = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertices [
              "a"
              "b"
            ];
            importGraph = engine.overlay (engine.edge "a" "b") (engine.edge "b" "a");
          };
          r = engine.evalDebug {
            baseNodes = n;
            attributes = {
              # a.ping reads b.ping, b.ping reads a.ping → cycle.
              ping =
                self: id:
                let
                  other = builtins.head self.nodes.${id}.imports;
                in
                self.evaluated.${other}.get "ping";
            };
          };
          tried = builtins.tryEval (r.evaluated.a.get "ping");
        in
        tried.success;
      expected = false;
    };

    # Verify the cycle error message contains the cycle path.
    # We can't inspect the message directly, but we can verify it throws.
    test-cycle-self-reference = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "x";
          };
          r = engine.evalDebug {
            baseNodes = n;
            attributes = {
              loop = self: id: self.evaluated.${id}.get "loop";
            };
          };
          tried = builtins.tryEval (r.evaluated.x.get "loop");
        in
        tried.success;
      expected = false;
    };

    # HOAG synthesis works with evalDebug.
    test-hoag-with-debug = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertex "root";
            decls = {
              root = {
                val = 42;
              };
            };
          };
          r = engine.evalDebug {
            baseNodes = n;
            synthesize =
              self:
              {
                "synth" = {
                  id = "synth";
                  parent = "root";
                  decls = {
                    origin = "synthesized";
                  };
                  imports = [ ];
                  childrenIds = [ ];
                  type = null;
                };
              };
            attributes = { };
          };
        in
        r.nodes.synth.decls.origin;
      expected = "synthesized";
    };
  };
}
