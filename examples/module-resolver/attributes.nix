# Module resolver attributes.
#
# lookup: parameterized name resolution via scope graph query.
# visibleDecls: all visible declarations with inner-shadows-outer.
# moduleCount: synthesized count of reachable modules.
{ engine, lib }:
{
  # Lookup a declaration name. Walks: local decls → imports → parent chain.
  lookup = engine.paramAttr (
    self: id: name:
    engine.query {
      dataFilter = node: node.decls.${name} or null;
    } self id
  );

  # All visible declarations from this scope (local + imports + parent).
  visibleDecls =
    self: id:
    let
      node = self.nodes.${id};
      local = node.decls;
      importedDecls = lib.foldl' (acc: iid: engine.shadow (self.nodes.${iid}.decls) acc) { } node.imports;
      parentDecls = if node.parent != null then self.evaluated.${node.parent}.get "visibleDecls" else { };
    in
    engine.shadow local (engine.shadow importedDecls parentDecls);

  # Count modules reachable from this scope.
  moduleCount = self: id: builtins.length (engine.descendants self id);
}
