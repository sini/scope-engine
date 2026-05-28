# Type checker attributes.
#
# allFields: collect all fields including inherited via R and E edges.
# fields, fieldCount: attribute wrappers for allFields.
# typeKind: parameterized type namespace lookup via scoped relations.
{ engine, lib }:
let
  # Collect all fields for a record/class, including inherited via R and E edges.
  allFields =
    self: id:
    let
      node = self.node id;
      local = builtins.removeAttrs node.decls [ "__edges" ];
      rFields = lib.foldl' (acc: rid: engine.shadow acc (allFields self rid)) { } (
        engine.followEdge "R" self id
      );
      eFields = lib.foldl' (acc: eid: engine.shadow acc (allFields self eid)) { } (
        engine.followEdge "E" self id
      );
    in
    engine.shadow local (engine.shadow rFields eFields);
in
{
  fields = allFields;

  fieldCount = self: id: builtins.length (builtins.attrNames (allFields self id));

  # Type lookup in root's type namespace (scoped relations stored in decls).
  typeKind = engine.paramAttr (
    self: _id: typeName:
    let
      root = self.node "root";
    in
    (root.decls.__typeDecl or { }).${typeName} or "unknown"
  );
}
