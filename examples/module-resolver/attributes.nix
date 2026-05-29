# Module resolver attributes.
#
# lookup: parameterized name resolution via scope graph query.
# visibleDecls: all visible declarations with inner-shadows-outer.
# moduleCount: synthesized count of reachable modules.
{
  genScope,
  lib,
  roots,
}:
{
  children = _self: id: lib.filterAttrs (_: n: n.parent == id) roots;
  imports = _self: id: (_self.node id).decls.__edges.I or [ ];

  # Lookup a declaration name. Walks: local decls → imports → parent chain.
  lookup = genScope.paramAttr (
    self: id: name:
    genScope.query {
      dataFilter = node: node.decls.${name} or null;
    } self id
  );

  # All visible declarations from this scope (local + imports + parent).
  visibleDecls =
    self: id:
    let
      node = self.node id;
      local = builtins.removeAttrs node.decls [ "__edges" ];
      importIds = self.get id "imports";
      importedDecls = lib.foldl' (
        acc: iid: genScope.shadow (builtins.removeAttrs (self.node iid).decls [ "__edges" ]) acc
      ) { } importIds;
      parentDecls = if node.parent != null then self.get node.parent "visibleDecls" else { };
    in
    genScope.shadow local (genScope.shadow importedDecls parentDecls);

  # Count modules reachable from this scope.
  moduleCount = self: id: builtins.length (genScope.descendants self id);
}
