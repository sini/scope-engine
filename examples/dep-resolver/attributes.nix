# Dependency resolver attributes.
{ genScope, lib }:
{
  availableAPIs =
    self: id:
    let
      node = self.node id;
      own = node.decls.exports or [ ];
      imported = genScope.collectImports (self: iid: (self.node iid).decls.exports or [ ]) self id;
    in
    lib.unique (own ++ imported);

  depDepth =
    self: id:
    let
      importIds = self.get id "imports";
      childDepths = map (iid: self.get iid "depDepth") importIds;
    in
    if childDepths == [ ] then 0 else 1 + lib.foldl' (a: b: if a > b then a else b) 0 childDepths;

  depCount =
    self: id:
    let
      direct = self.get id "imports";
      transitive = lib.concatMap (iid: self.get iid "allDeps") direct;
    in
    builtins.length (lib.unique (direct ++ transitive));

  allDeps =
    self: id:
    let
      direct = self.get id "imports";
      transitive = lib.concatMap (iid: self.get iid "allDeps") direct;
    in
    lib.unique (direct ++ transitive);
}
