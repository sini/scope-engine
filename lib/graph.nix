# Algebraic graph primitives (Mokhov, 2017).
#
# Four core operations: empty, vertex, overlay, connect.
# Overlay is commutative, associative, idempotent.
# Connect distributes over overlay; cross-product edges.
# Vertices may contain duplicates; dedup is deferred to buildNodes where
# it is cheap via genAttrs (exploits Mokhov's algebraic idempotence: x + x = x).
let
  empty = {
    vertices = [ ];
    edges = [ ];
  };

  vertex = id: {
    vertices = [ id ];
    edges = [ ];
  };

  # Mokhov's connect: cross-product edges from all vertices in g1 to all in g2.
  connect = g1: g2: {
    vertices = g1.vertices ++ g2.vertices;
    edges =
      g1.edges
      ++ g2.edges
      ++ builtins.concatMap (
        a:
        map (b: {
          from = a;
          to = b;
        }) g2.vertices
      ) g1.vertices;
  };

  # Monoidal overlay: commutative, associative, idempotent.
  overlay = g1: g2: {
    vertices = g1.vertices ++ g2.vertices;
    edges = g1.edges ++ g2.edges;
  };

  # Derived constructors.
  overlays = gs: builtins.foldl' overlay empty gs;
  vertices = vs: overlays (map vertex vs);
  edge = from: to: connect (vertex from) (vertex to);
  edges = es: overlays (map (e: edge e.from e.to) es);
  # Mokhov 2017 §5.1: path xs = edges (zip xs (tail xs)). O(n).
  path =
    vs:
    if vs == [ ] then
      empty
    else if builtins.length vs == 1 then
      vertex (builtins.head vs)
    else
      let
        pairs = builtins.genList (i: {
          from = builtins.elemAt vs i;
          to = builtins.elemAt vs (i + 1);
        }) (builtins.length vs - 1);
      in
      edges pairs;
  circuit = vs: if vs == [ ] then empty else path (vs ++ [ (builtins.head vs) ]);
  # Mokhov 2017 §5.1 defines star as center→leaves. Inverted here: leaves→center.
  # Convention: parent edges point from child to parent.
  star = center: leaves: connect (vertices leaves) (vertex center);
  clique = vs: builtins.foldl' connect empty (map vertex vs);
  # Construct graph from recursive tree structure (Mokhov 2017 §5.1).
  # Input: { root: string, children: [tree] } where tree = { root, children }.
  tree =
    t:
    let
      childRoots = map (c: c.root) t.children;
      childGraphs = map tree t.children;
    in
    overlays ([ (star t.root childRoots) ] ++ childGraphs);
  # Construct graph from a list of trees (forest).
  forest = ts: overlays (map tree ts);
  # Flip all edge directions.
  transpose = graph: {
    inherit (graph) vertices;
    edges = map (e: {
      from = e.to;
      to = e.from;
    }) graph.edges;
  };
  # Membership predicates.
  hasVertex = v: graph: builtins.elem v graph.vertices;
  hasEdge =
    from: to: graph:
    builtins.any (e: e.from == from && e.to == to) graph.edges;
  # Graph removal operations.
  removeVertex = v: induce (x: x != v);
  removeEdge = efrom: eto: graph: {
    inherit (graph) vertices;
    edges = builtins.filter (e: !(e.from == efrom && e.to == eto)) graph.edges;
  };

  # Map over vertices.
  gmap = f: graph: {
    vertices = map f graph.vertices;
    edges = map (e: {
      from = f e.from;
      to = f e.to;
    }) graph.edges;
  };

  # Filter to subgraph matching predicate.
  induce = pred: graph: {
    vertices = builtins.filter pred graph.vertices;
    edges = builtins.filter (e: pred e.from && pred e.to) graph.edges;
  };

in
{
  inherit
    empty
    vertex
    connect
    overlay
    overlays
    vertices
    edge
    edges
    path
    circuit
    star
    clique
    tree
    forest
    gmap
    induce
    transpose
    hasVertex
    hasEdge
    removeVertex
    removeEdge
    ;
}
