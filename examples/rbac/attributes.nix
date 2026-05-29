# RBAC attributes.
#
# rolePermissions is exported alongside attributes because tests need
# it directly for verifying the role hierarchy resolution.
{
  genScope,
  lib,
  roots,
}:
let
  # Collect all permissions for a role, including inherited via R edges.
  rolePermissions =
    self: roleId:
    let
      node = self.node roleId;
      local = lib.filterAttrs (k: v: k != "__edges" && v == true) node.decls;
      inherited = lib.foldl' (acc: rid: acc // (rolePermissions self rid)) { } (
        genScope.followEdge "R" self roleId
      );
    in
    local // inherited;
in
{
  inherit rolePermissions;

  attributes = {
    children = _self: id: lib.filterAttrs (_: n: n.parent == id) roots;
    imports = _self: _id: [ ];
    "edges-R" = _self: id: (_self.node id).decls.__edges.R or [ ];
    "edges-A" = _self: id: (_self.node id).decls.__edges.A or [ ];
    "edges-D" = _self: id: (_self.node id).decls.__edges.D or [ ];

    permissions =
      self: id:
      lib.foldl' (acc: rid: acc // (rolePermissions self rid)) { } (genScope.followEdge "A" self id);

    hasPermission = genScope.paramAttr (
      self: id: perm:
      (self.get id "permissions").${perm} or false
    );

    isDenied = genScope.paramAttr (
      self: id: args:
      builtins.elem args.action (((self.node id).decls.__deny or { }).${args.resource} or [ ])
    );

    canAccess = genScope.paramAttr (
      self: id: args:
      let
        hasPerm = self.get id "hasPermission" args.action;
        denied = self.get id "isDenied" args;
      in
      hasPerm && !denied
    );

    sensitivity = genScope.inherit' { resolve = node: node.decls.sensitivity or null; };
  };
}
