# Type checker attributes.
#
# allFields: collect all fields including inherited via R and E edges.
# fields, fieldCount: attribute wrappers for allFields.
# typeKind: parameterized type namespace lookup via scoped relations.
{ genScope, lib }:
let
  # Collect all fields for a record/class, including inherited via R and E edges.
  allFields =
    self: id:
    let
      node = self.node id;
      local = builtins.removeAttrs node.decls [ "__edges" ];
      rFields = lib.foldl' (acc: rid: genScope.shadow acc (allFields self rid)) { } (
        genScope.followEdge "R" self id
      );
      eFields = lib.foldl' (acc: eid: genScope.shadow acc (allFields self eid)) { } (
        genScope.followEdge "E" self id
      );
    in
    genScope.shadow local (genScope.shadow rFields eFields);
in
{
  fields = allFields;

  fieldCount = self: id: builtins.length (builtins.attrNames (allFields self id));

  # Type lookup in root's type namespace (scoped relations stored in decls).
  typeKind = genScope.paramAttr (
    self: _id: typeName:
    let
      root = self.node "root";
    in
    (root.decls.__typeDecl or { }).${typeName} or "unknown"
  );
}
