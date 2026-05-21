# Dependency resolver attributes.
{ engine, lib }:
{
  availableAPIs = self: id:
    let
      node = self.nodes.${id};
      own = node.decls.exports or [ ];
      imported = engine.collectImports
        (self: iid: self.evaluated.${iid}.get "availableAPIs") self id;
    in
    lib.unique (own ++ imported);

  depDepth = self: id:
    let
      childDepths = map (iid: self.evaluated.${iid}.get "depDepth") self.nodes.${id}.imports;
    in
    if childDepths == [ ] then 0
    else 1 + lib.foldl' (a: b: if a > b then a else b) 0 childDepths;

  depCount = self: id:
    let
      direct = self.nodes.${id}.imports;
      transitive = lib.concatMap (iid: self.evaluated.${iid}.get "allDeps") direct;
    in
    builtins.length (lib.unique (direct ++ transitive));

  allDeps = self: id:
    let
      direct = self.nodes.${id}.imports;
      transitive = lib.concatMap (iid: self.evaluated.${iid}.get "allDeps") direct;
    in
    lib.unique (direct ++ transitive);
}
