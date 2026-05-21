# RBAC attributes.
{ engine, lib }:
let
  # Collect all permissions for a role, including inherited via R edges.
  rolePermissions = self: roleId:
    let
      node = self.nodes.${roleId};
      local = lib.filterAttrs (_: v: v == true) node.decls;
      inherited = lib.foldl' (acc: rid:
        acc // (rolePermissions self rid)
      ) { } (engine.followEdge "R" self roleId);
    in
    local // inherited;
in
{
  inherit rolePermissions;
  attributes = {
    permissions = self: id:
      let
        roleIds = engine.followEdge "A" self id;
      in
      lib.foldl' (acc: rid: acc // (rolePermissions self rid)) { } roleIds;

    hasPermission = engine.paramAttr (self: id: perm:
      let perms = self.evaluated.${id}.get "permissions";
      in perms.${perm} or false);

    isDenied = engine.paramAttr (self: id: args:
      let denyList = (self.nodes.${id}.rels.deny or { }).${args.resource} or [ ];
      in builtins.elem args.action denyList);

    canAccess = engine.paramAttr (self: id: args:
      let
        hasPerm = self.evaluated.${id}.get "hasPermission" args.action;
        denied = self.evaluated.${id}.get "isDenied" args;
      in hasPerm && !denied);

    sensitivity = engine.inherit_ { resolve = node: node.decls.sensitivity or null; };
  };
}
