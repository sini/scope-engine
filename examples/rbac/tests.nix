# RBAC tests.
{ engine, lib, result, rolePermissions }:
{
  viewer-perms = rolePermissions result "viewer";
  editor-perms = let p = rolePermissions result "editor"; in builtins.sort builtins.lessThan (builtins.attrNames p);
  admin-perms = let p = rolePermissions result "admin"; in builtins.sort builtins.lessThan (builtins.attrNames p);
  auditor-perms = let p = rolePermissions result "auditor"; in builtins.sort builtins.lessThan (builtins.attrNames p);

  alice-perms = let p = result.evaluated.alice.get "permissions"; in builtins.sort builtins.lessThan (builtins.attrNames p);
  bob-perms = let p = result.evaluated.bob.get "permissions"; in builtins.sort builtins.lessThan (builtins.attrNames p);
  carol-perms = let p = result.evaluated.carol.get "permissions"; in builtins.attrNames p;

  alice-can-delete = result.evaluated.alice.get "hasPermission" "delete";
  carol-cannot-write = result.evaluated.carol.get "hasPermission" "write";
  bob-can-audit = result.evaluated.bob.get "hasPermission" "audit";
  bob-cannot-manage = result.evaluated.bob.get "hasPermission" "manage";

  dave-denied-delete = result.evaluated.dave.get "isDenied" { resource = "project-x"; action = "delete"; };
  dave-not-denied-read = result.evaluated.dave.get "isDenied" { resource = "project-x"; action = "read"; };
  dave-can-read-project-x = result.evaluated.dave.get "canAccess" { resource = "project-x"; action = "read"; };
  dave-cannot-manage-project-x = result.evaluated.dave.get "canAccess" { resource = "project-x"; action = "manage"; };

  doc1-sensitivity = result.evaluated."doc-1".get "sensitivity";
  doc3-sensitivity = result.evaluated."doc-3".get "sensitivity";
  org-sensitivity = result.evaluated.org.get "sensitivity";
  project-x-docs = builtins.sort builtins.lessThan (engine.childrenIds result "project-x");
  doc1-ancestors = engine.ancestors result "doc-1";

  all-users = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "user"));
  all-roles = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "role"));
  all-resources = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "resource"));
  bob-role-count = builtins.length (engine.followEdge "A" result "bob");
  alice-role-count = builtins.length (engine.followEdge "A" result "alice");

  # collectByType: all roles via typed collection
  role-names-via-collect = builtins.sort builtins.lessThan (
    engine.collectByType "role" (self: id: [ id ]) result);

  # collectByLabel: alice's role names via A edges
  alice-roles-via-label = engine.collectByLabel "A"
    (self: id: [ id ]) result "alice";
}
