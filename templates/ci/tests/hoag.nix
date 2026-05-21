{ lib, engine, ... }:
let
  parentGraph = engine.vertices [
    "dept:eng"
    "dept:sales"
  ];

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      "dept:eng" = {
        budget = 500000;
      };
      "dept:sales" = {
        budget = 200000;
      };
    };
  };

  # Synthesize review nodes for departments exceeding budget threshold.
  synthesize =
    self:
    let
      depts = lib.filterAttrs (id: _: lib.hasPrefix "dept:" id) self.nodes;
    in
    lib.concatMapAttrs (
      id: node:
      if (node.decls.budget or 0) > 300000 then
        {
          "review:${id}" = {
            inherit id;
            parent = id;
            decls = {
              reviewer = "finance";
              threshold = 300000;
            };
            imports = [ ];
            childrenIds = [ ];
            type = "review";
          };
        }
      else
        { }
    ) depts;

  result = engine.eval {
    inherit baseNodes synthesize;
    attributes = { };
  };
in
{
  hoag = {
    test-synthesized-node-exists = {
      expr = result.nodes ? "review:dept:eng";
      expected = true;
    };

    test-synthesized-node-not-for-low-budget = {
      expr = result.nodes ? "review:dept:sales";
      expected = false;
    };

    test-synthesized-node-data = {
      expr = result.nodes."review:dept:eng".decls.reviewer;
      expected = "finance";
    };

    test-base-nodes-not-overwritten = {
      expr =
        let
          badSynthesize = _: {
            "dept:eng" = {
              id = "dept:eng";
              parent = null;
              decls = {
                budget = 0;
              };
              imports = [ ];
              childrenIds = [ ];
              type = null;
            };
          };
          r = engine.eval {
            inherit baseNodes;
            synthesize = badSynthesize;
            attributes = { };
          };
        in
        r.nodes."dept:eng".decls.budget;
      expected = 500000;
    };
  };
}
