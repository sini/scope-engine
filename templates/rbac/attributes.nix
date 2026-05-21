# RBAC attributes.
#
# rolePermissions is exported alongside attributes because tests need
# it directly for verifying the role hierarchy resolution.
{ engine, lib }:
let
  # Collect all permissions for a role, including inherited via R edges.
  rolePermissions =
    self: roleId:
    let
      node = self.nodes.${roleId};
      local = lib.filterAttrs (_: v: v == true) node.decls;
      inherited = lib.foldl' (
        acc: rid: acc // (rolePermissions self rid)
      ) { } (engine.followEdge "R" self roleId);
    in
    local // inherited;
in
{
  inherit rolePermissions;

  attributes = {
    permissions =
      self: id:
      lib.foldl' (acc: rid: acc // (rolePermissions self rid)) { }
        (engine.followEdge "A" self id);

    hasPermission = engine.paramAttr (
      self: id: perm:
      (self.evaluated.${id}.get "permissions").${perm} or false
    );

    isDenied = engine.paramAttr (
      self: id: args:
      builtins.elem args.action ((self.nodes.${id}.rels.deny or { }).${args.resource} or [ ])
    );

    canAccess = engine.paramAttr (
      self: id: args:
      let
        hasPerm = self.evaluated.${id}.get "hasPermission" args.action;
        denied = self.evaluated.${id}.get "isDenied" args;
      in
      hasPerm && !denied
    );

    sensitivity = engine.inherit_ { resolve = node: node.decls.sensitivity or null; };
  };
}
