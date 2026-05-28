# RBAC tests.
{
  engine,
  lib,
  result,
  rolePermissions,
}:
{
  viewer-perms = rolePermissions result "viewer";
  editor-perms =
    let
      p = rolePermissions result "editor";
    in
    builtins.sort builtins.lessThan (builtins.attrNames p);
  admin-perms =
    let
      p = rolePermissions result "admin";
    in
    builtins.sort builtins.lessThan (builtins.attrNames p);
  auditor-perms =
    let
      p = rolePermissions result "auditor";
    in
    builtins.sort builtins.lessThan (builtins.attrNames p);

  alice-perms =
    let
      p = result.get "alice" "permissions";
    in
    builtins.sort builtins.lessThan (builtins.attrNames p);
  bob-perms =
    let
      p = result.get "bob" "permissions";
    in
    builtins.sort builtins.lessThan (builtins.attrNames p);
  carol-perms =
    let
      p = result.get "carol" "permissions";
    in
    builtins.attrNames p;

  alice-can-delete = result.get "alice" "hasPermission" "delete";
  carol-cannot-write = result.get "carol" "hasPermission" "write";
  bob-can-audit = result.get "bob" "hasPermission" "audit";
  bob-cannot-manage = result.get "bob" "hasPermission" "manage";

  dave-denied-delete = result.get "dave" "isDenied" {
    resource = "project-x";
    action = "delete";
  };
  dave-not-denied-read = result.get "dave" "isDenied" {
    resource = "project-x";
    action = "read";
  };
  dave-can-read-project-x = result.get "dave" "canAccess" {
    resource = "project-x";
    action = "read";
  };
  dave-cannot-manage-project-x = result.get "dave" "canAccess" {
    resource = "project-x";
    action = "manage";
  };

  doc1-sensitivity = result.get "doc-1" "sensitivity";
  doc3-sensitivity = result.get "doc-3" "sensitivity";
  org-sensitivity = result.get "org" "sensitivity";
  project-x-docs = builtins.sort builtins.lessThan (engine.childrenIds result "project-x");
  doc1-ancestors = engine.ancestors result "doc-1";

  all-users = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "user"));
  all-roles = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "role"));
  all-resources = builtins.sort builtins.lessThan (
    builtins.attrNames (engine.nodesByType result "resource")
  );
  bob-role-count = builtins.length (engine.followEdge "A" result "bob");
  alice-role-count = builtins.length (engine.followEdge "A" result "alice");

  # collectByType: all roles via typed collection
  role-names-via-collect = builtins.sort builtins.lessThan (
    engine.collectByType "role" (self: id: [ id ]) result
  );

  # collectByLabel: alice's role names via A edges
  alice-roles-via-label = engine.collectByLabel "A" (self: id: [ id ]) result "alice";
}
