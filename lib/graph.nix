# Algebraic graph primitives (Mokhov, 2017).
#
# Four core operations: empty, vertex, overlay, connect.
# Overlay is commutative, associative, idempotent.
# Connect distributes over overlay; cross-product edges.
# Vertex dedup deferred to buildNodes (exploits algebraic idempotence).
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
  connect =
    g1: g2: {
      vertices = g1.vertices ++ g2.vertices;
      edges =
        g1.edges
        ++ g2.edges
        ++ builtins.concatMap (a: map (b: { from = a; to = b; }) g2.vertices) g1.vertices;
    };

  # Monoidal overlay: commutative, associative, idempotent.
  overlay =
    g1: g2: {
      vertices = g1.vertices ++ g2.vertices;
      edges = g1.edges ++ g2.edges;
    };

  # Derived constructors.
  vertices = vs: builtins.foldl' overlay empty (map vertex vs);
  edge = from: to: connect (vertex from) (vertex to);
  star = center: leaves: connect (vertices leaves) (vertex center);
  clique = vs: builtins.foldl' connect empty (map vertex vs);

  # Map over vertices.
  gmap =
    f: graph: {
      vertices = map f graph.vertices;
      edges = map (e: {
        from = f e.from;
        to = f e.to;
      }) graph.edges;
    };

  # Filter to subgraph matching predicate.
  induce =
    pred: graph: {
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
    vertices
    edge
    star
    clique
    gmap
    induce
    ;
}
