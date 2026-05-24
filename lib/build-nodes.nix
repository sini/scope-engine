# Scope graph construction from labeled algebraic graphs.
#
# Builds a flat node map from separate parent and import edge graphs.
# Construction complexity: O(V + E) via pre-indexed edge grouping.
#
# Supports custom edge labels (van Antwerpen 2018 §2.1) via edgeGraphs.
# The parentGraph/importGraph API is sugar for edgeGraphs.P / edgeGraphs.I.
{ lib }:
let
  graph = import ./graph.nix;

  # Build flat node map from labeled algebraic graphs (Mokhov §7).
  # Supports scoped relations (van Antwerpen 2018 §2.1): multiple named
  # relations per scope via `relations` parameter. `decls` is the default
  # ":" relation for backwards compatibility.
  buildNodes =
    {
      parentGraph ? graph.empty,
      importGraph ? graph.empty,
      # Custom edge labels: { labelName → algebraicGraph }.
      # P and I are populated from parentGraph/importGraph if not provided here.
      edgeGraphs ? { },
      decls ? { },
      types ? { },
      relations ? { },
    }:
    let
      # Merge explicit edgeGraphs with parentGraph/importGraph sugar.
      allEdgeGraphs =
        (lib.optionalAttrs (parentGraph.vertices != [ ] || parentGraph.edges != [ ]) {
          P = parentGraph;
        })
        // (lib.optionalAttrs (importGraph.vertices != [ ] || importGraph.edges != [ ]) {
          I = importGraph;
        })
        // edgeGraphs;

      # Collect all vertices across all edge graphs.
      allVertices = lib.unique (
        lib.concatMap (label: allEdgeGraphs.${label}.vertices) (builtins.attrNames allEdgeGraphs)
      );

      # Pre-index edges by label, grouped by from and to.
      edgeIndex = lib.mapAttrs (
        _label: g: {
          byFrom = builtins.groupBy (e: e.from) g.edges;
          byTo = builtins.groupBy (e: e.to) g.edges;
        }
      ) allEdgeGraphs;

      # Helper: get targets of edges from a node for a given label.
      edgeTargets = label: id:
        if edgeIndex ? ${label} then
          map (e: e.to) (edgeIndex.${label}.byFrom.${id} or [ ])
        else
          [ ];

      # Helper: get sources of edges to a node for a given label.
      edgeSources = label: id:
        if edgeIndex ? ${label} then
          map (e: e.from) (edgeIndex.${label}.byTo.${id} or [ ])
        else
          [ ];

    in
    lib.genAttrs allVertices (
      id:
      {
        inherit id;
        type = types.${id} or null;
        # Parent from P edges. P(S) is a partial function (Neron §2.2) — at most one parent.
        parent =
          let
            targets = edgeTargets "P" id;
          in
          if builtins.length targets > 1 then
            throw "gen-scope: node '${id}' has ${toString (builtins.length targets)} parent edges (P must be a partial function, Neron §2.2)"
          else if targets != [ ] then builtins.head targets
          else null;
        # Backwards-compatible: imports from I edges.
        imports = edgeTargets "I" id;
        decls = decls.${id} or { };
        # Scoped relations: { relationName → data } per node.
        rels = (relations.${id} or { }) // (
          let
            d = decls.${id} or { };
          in
          lib.optionalAttrs (d != { }) { ":" = d; }
        );
        # Backwards-compatible: children from P edges (reverse).
        childrenIds = edgeSources "P" id;
        # All labeled edges from this node: { label → [targetId] }.
        # Includes P, I, and any custom labels.
        edgesByLabel = lib.mapAttrs (label: _: edgeTargets label id) allEdgeGraphs;
      }
    );
in
{
  inherit buildNodes;
}
