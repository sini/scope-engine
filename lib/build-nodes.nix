# Scope graph construction: produces minimal root descriptors from algebraic graphs.
#
# Output shape: { id = { id, type, parent, decls }; }
# No pre-indexed edges — relationships are computed via attributes.
# Edge declarations stored in decls.__edges for consumers to use in attribute definitions.
{ lib }:
let
  graph = import ./graph.nix;

  buildNodes =
    {
      parentGraph ? graph.empty,
      importGraph ? graph.empty,
      edgeGraphs ? { },
      decls ? { },
      types ? { },
      strict ? true,
    }:
    let
      # Merge all edge graphs for vertex collection
      allEdgeGraphs =
        (lib.optionalAttrs (parentGraph.vertices != [ ] || parentGraph.edges != [ ]) { P = parentGraph; })
        // (lib.optionalAttrs (importGraph.vertices != [ ] || importGraph.edges != [ ]) {
          I = importGraph;
        })
        // edgeGraphs;

      # Collect all vertices: from edge graphs + decls + types keys (O(n) dedup via attrset)
      allVertices = builtins.attrNames (
        builtins.listToAttrs (
          lib.concatMap (
            label:
            map (v: {
              name = v;
              value = true;
            }) allEdgeGraphs.${label}.vertices
          ) (builtins.attrNames allEdgeGraphs)
          ++ map (v: {
            name = v;
            value = true;
          }) (builtins.attrNames decls)
          ++ map (v: {
            name = v;
            value = true;
          }) (builtins.attrNames types)
        )
      );

      # Pre-index P edges by source (child → parent).
      # Uses groupBy (O(E)) then validates partial function constraint.
      # strict=true: deepSeq forces all validations upfront (errors surface immediately).
      # strict=false: validation is lazy (errors surface only when conflicting node's parent is accessed).
      parentIndex =
        let
          grouped = builtins.groupBy (e: e.from) (allEdgeGraphs.P.edges or [ ]);
          validated = lib.mapAttrs (
            from: edges:
            if builtins.length edges > 1 then
              throw "gen-scope: node '${from}' has ${toString (builtins.length edges)} parent edges (P must be a partial function, Neron §2.2). If this node should exist under multiple parents, use distinct IDs (e.g., '${from}@parent1', '${from}@parent2')."
            else
              (builtins.head edges).to
          ) grouped;
        in
        if strict then builtins.deepSeq validated validated else validated;

      # Pre-index all non-P edges by source, grouped by label
      edgeIndex = lib.mapAttrs (
        _label: g:
        builtins.foldl' (acc: e: acc // { ${e.from} = (acc.${e.from} or [ ]) ++ [ e.to ]; }) { } g.edges
      ) (builtins.removeAttrs allEdgeGraphs [ "P" ]);
    in
    builtins.seq parentIndex (
      lib.genAttrs allVertices (id: {
        inherit id;
        type = types.${id} or null;
        parent = parentIndex.${id} or null;
        decls = (decls.${id} or { }) // {
          # Store edge declarations for consumers to build computed attributes from
          __edges = lib.mapAttrs (label: idx: idx.${id} or [ ]) edgeIndex;
        };
      })
    );
in
{
  inherit buildNodes;
}
