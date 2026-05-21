{
  description = "RBAC permission resolver: role hierarchies and resource access control via scope graphs";

  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };

      # ═══════════════════════════════════════════════════════════════
      # Role-Based Access Control via scope graphs
      #
      # Roles form a hierarchy: admin inherits from editor inherits
      # from viewer. Users are assigned roles via import edges.
      # Resources have permission scopes. Resolution determines
      # effective permissions through the role hierarchy.
      #
      # deny-overrides: deny at any level blocks access, modeled via
      # custom shadow policy (localShadowsImport = false for deny).
      #
      # Role hierarchy:
      #   viewer → can: read
      #   editor → inherits viewer, can: read, write
      #   admin  → inherits editor, can: read, write, delete, manage
      #   auditor → inherits viewer, can: read, audit (parallel hierarchy)
      #
      # Users:
      #   alice → admin
      #   bob   → editor + auditor (multiple roles)
      #   carol → viewer
      #   dave  → editor, but DENIED delete on project-x
      #
      # Resources:
      #   org/
      #   ├── project-x/
      #   │   ├── doc-1
      #   │   └── doc-2
      #   └── project-y/
      #       └── doc-3
      # ═══════════════════════════════════════════════════════════════

      baseNodes = engine.buildNodes {
        # Resource hierarchy: org → projects → documents (parent edges)
        parentGraph = engine.overlays [
          (engine.star "org" [ "project-x" "project-y" ])
          (engine.star "project-x" [ "doc-1" "doc-2" ])
          (engine.edge "doc-3" "project-y")
        ];
        edgeGraphs = {
          # R = role inheritance (like class extends in Neron 2015 §3, Fig. 16)
          R = engine.overlays [
            (engine.edge "editor" "viewer")
            (engine.edge "admin" "editor")
            (engine.edge "auditor" "viewer")
          ];
          # A = role assignment (user → role)
          A = engine.overlays [
            (engine.edge "alice" "admin")
            (engine.edge "bob" "editor")
            (engine.edge "bob" "auditor")
            (engine.edge "carol" "viewer")
            (engine.edge "dave" "editor")
          ];
          # D = deny override (user → resource with deny)
          D = engine.edge "dave" "project-x";
        };
        decls = {
          # Role permissions
          viewer  = { read = true; };
          editor  = { write = true; };
          admin   = { delete = true; manage = true; };
          auditor = { audit = true; };
          # User metadata
          alice = { email = "alice@corp.com"; };
          bob   = { email = "bob@corp.com"; };
          carol = { email = "carol@corp.com"; };
          dave  = { email = "dave@corp.com"; };
          # Resource metadata
          org = { name = "Acme Corp"; };
          "project-x" = { name = "Project X"; sensitivity = "high"; };
          "project-y" = { name = "Project Y"; sensitivity = "low"; };
          "doc-1" = { title = "Design doc"; };
          "doc-2" = { title = "API spec"; };
          "doc-3" = { title = "Roadmap"; };
        };
        types = {
          viewer = "role"; editor = "role"; admin = "role"; auditor = "role";
          alice = "user"; bob = "user"; carol = "user"; dave = "user";
          org = "resource"; "project-x" = "resource"; "project-y" = "resource";
          "doc-1" = "resource"; "doc-2" = "resource"; "doc-3" = "resource";
        };
        relations = {
          # Deny rules: dave is denied delete on project-x
          dave = { deny = { "project-x" = [ "delete" "manage" ]; }; };
        };
      };

      # Collect all permissions for a role, including inherited via R edges.
      rolePermissions = self: roleId:
        let
          node = self.nodes.${roleId};
          local = lib.filterAttrs (_: v: v == true) node.decls;
          inherited = lib.foldl' (acc: rid:
            acc // (rolePermissions self rid)
          ) {} (engine.followEdge "R" self roleId);
        in local // inherited;

      attributes = {
        # Effective permissions for a user (union of all assigned roles)
        permissions = self: id:
          let
            roleIds = engine.followEdge "A" self id;
            allPerms = lib.foldl' (acc: rid:
              acc // (rolePermissions self rid)
            ) {} roleIds;
          in allPerms;

        # Check if a user has a specific permission
        hasPermission = engine.paramAttr (self: id: perm:
          let perms = self.evaluated.${id}.get "permissions";
          in perms.${perm} or false);

        # Check if a user is denied a permission on a specific resource
        isDenied = engine.paramAttr (self: id: args:
          let
            resource = args.resource;
            action = args.action;
            denyList = (self.nodes.${id}.rels.deny or {}).${resource} or [];
          in builtins.elem action denyList);

        # Effective permission on a resource (permission AND NOT denied)
        canAccess = engine.paramAttr (self: id: args:
          let
            hasPerm = self.evaluated.${id}.get "hasPermission" args.action;
            denied = self.evaluated.${id}.get "isDenied" args;
          in hasPerm && !denied);

        # Resource sensitivity: inherited from parent resources
        sensitivity = engine.inherit_ {
          resolve = node: node.decls.sensitivity or null;
        };
      };

      result = engine.eval { inherit baseNodes attributes; };

    in
    {
      # ─── Role hierarchy resolution ──────────────────────────────────

      # Viewer has: read
      tests.viewer-perms =
        rolePermissions result "viewer";
        # → { read = true; }

      # Editor has: write + read (inherited from viewer)
      tests.editor-perms =
        let p = rolePermissions result "editor";
        in builtins.sort builtins.lessThan (builtins.attrNames p);
        # → [ "read" "write" ]

      # Admin has: delete, manage + write, read (inherited chain)
      tests.admin-perms =
        let p = rolePermissions result "admin";
        in builtins.sort builtins.lessThan (builtins.attrNames p);
        # → [ "delete" "manage" "read" "write" ]

      # Auditor has: audit + read (from viewer)
      tests.auditor-perms =
        let p = rolePermissions result "auditor";
        in builtins.sort builtins.lessThan (builtins.attrNames p);
        # → [ "audit" "read" ]

      # ─── User effective permissions ─────────────────────────────────

      # Alice is admin: full permissions
      tests.alice-perms =
        let p = result.evaluated.alice.get "permissions";
        in builtins.sort builtins.lessThan (builtins.attrNames p);
        # → [ "delete" "manage" "read" "write" ]

      # Bob is editor + auditor: union of both role hierarchies
      tests.bob-perms =
        let p = result.evaluated.bob.get "permissions";
        in builtins.sort builtins.lessThan (builtins.attrNames p);
        # → [ "audit" "read" "write" ]

      # Carol is viewer: read only
      tests.carol-perms =
        let p = result.evaluated.carol.get "permissions";
        in builtins.attrNames p;
        # → [ "read" ]

      # ─── Permission checks ─────────────────────────────────────────

      tests.alice-can-delete = result.evaluated.alice.get "hasPermission" "delete"; # true
      tests.carol-cannot-write = result.evaluated.carol.get "hasPermission" "write"; # false
      tests.bob-can-audit = result.evaluated.bob.get "hasPermission" "audit"; # true
      tests.bob-cannot-manage = result.evaluated.bob.get "hasPermission" "manage"; # false

      # ─── Deny overrides ────────────────────────────────────────────

      # Dave is editor (has delete=false anyway, but has write).
      # Dave is denied delete and manage on project-x.
      tests.dave-denied-delete =
        result.evaluated.dave.get "isDenied" { resource = "project-x"; action = "delete"; };
        # → true

      tests.dave-not-denied-read =
        result.evaluated.dave.get "isDenied" { resource = "project-x"; action = "read"; };
        # → false

      # canAccess: combines permission check with deny
      tests.dave-can-read-project-x =
        result.evaluated.dave.get "canAccess" { resource = "project-x"; action = "read"; };
        # → true

      tests.dave-cannot-manage-project-x =
        result.evaluated.dave.get "canAccess" { resource = "project-x"; action = "manage"; };
        # → false (denied even if he had the perm)

      # ─── Resource hierarchy ─────────────────────────────────────────

      # Documents inherit sensitivity from project
      tests.doc1-sensitivity =
        result.evaluated."doc-1".get "sensitivity";
        # → "high" (inherited from project-x)

      tests.doc3-sensitivity =
        result.evaluated."doc-3".get "sensitivity";
        # → "low" (inherited from project-y)

      tests.org-sensitivity =
        result.evaluated.org.get "sensitivity";
        # → null (not set at org level)

      # Resource tree structure
      tests.project-x-docs =
        builtins.sort builtins.lessThan (engine.childrenIds result "project-x");
        # → [ "doc-1" "doc-2" ]

      tests.doc1-ancestors =
        engine.ancestors result "doc-1";
        # → [ "project-x" "org" ]

      # ─── Typed queries ──────────────────────────────────────────────

      tests.all-users =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "user"));
        # → [ "alice" "bob" "carol" "dave" ]

      tests.all-roles =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "role"));
        # → [ "admin" "auditor" "editor" "viewer" ]

      tests.all-resources =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "resource"));
        # → [ "doc-1" "doc-2" "doc-3" "org" "project-x" "project-y" ]

      # ─── Multi-role assignment detection ────────────────────────────

      tests.bob-role-count =
        builtins.length (engine.followEdge "A" result "bob");
        # → 2 (editor + auditor)

      tests.alice-role-count =
        builtins.length (engine.followEdge "A" result "alice");
        # → 1 (admin only)
    };
}
