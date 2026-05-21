# Scope graph construction from labeled algebraic graphs.
#
# Builds a flat node map from separate parent and import edge graphs.
# Construction complexity: O(V + E) via pre-indexed edge grouping.
{ lib }:
let
  graph = import ./graph.nix;

  # Build flat node map from labeled algebraic graphs (Mokhov §7).
  buildNodes =
    {
      parentGraph,
      importGraph ? graph.empty,
      decls ? { },
      types ? { },
    }:
    let
      allVertices = lib.unique (parentGraph.vertices ++ importGraph.vertices);
      parentByFrom = builtins.groupBy (e: e.from) parentGraph.edges;
      parentByTo = builtins.groupBy (e: e.to) parentGraph.edges;
      importByFrom = builtins.groupBy (e: e.from) importGraph.edges;
    in
    lib.genAttrs allVertices (
      id:
      {
        inherit id;
        type = types.${id} or null;
        parent =
          let
            edges = parentByFrom.${id} or [ ];
          in
          if edges != [ ] then (builtins.head edges).to else null;
        imports = map (e: e.to) (importByFrom.${id} or [ ]);
        decls = decls.${id} or { };
        childrenIds = map (e: e.from) (parentByTo.${id} or [ ]);
      }
    );
in
{
  inherit buildNodes;
}
