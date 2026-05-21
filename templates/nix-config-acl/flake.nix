{
  description = "nix-config ACL: unified access control with three-level scope graph resolution";

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
      # nix-config ACL topology (from docs/ACL.md)
      #
      # Three-level resolution:
      #   groups                              ← shared definitions (kanidm, unix, system scopes)
      #     |
      #   environments.<env>.access           ← user → [group] bindings per environment
      #     |
      #   env.system-access-groups            ← env-wide baseline login gates
      #     + host.system-access-groups       ← host-specific login gates (merged with env)
      #     |
      #   resolved user                       ← enable + systemGroups derived from above
      #
      # Scope graph mapping:
      #   - Groups: nodes with I edges for members (transitive membership)
      #   - Environments: parent scopes for hosts
      #   - Hosts: children of environments with system-access-groups
      #   - Users: resolved per-host via attribute evaluation
      #   - Custom edge labels: M (membership), A (access binding), G (gate)
      # ═══════════════════════════════════════════════════════════════

      # ─── Group definitions ──────────────────────────────────────────
      # groups.<name> = { scope, description, members }
      # members creates transitive membership via M (membership) edges

      groups = {
        # Identity (kanidm)
        admins = { scope = "kanidm"; description = "Full administrative access"; members = []; };
        users  = { scope = "kanidm"; description = "Standard user access"; members = [ "admins" ]; };

        # System login gates (opt-in — not inherited from identity groups)
        system-access      = { scope = "system"; description = "Login access to all hosts"; members = []; };
        workstation-access = { scope = "system"; description = "Login access to workstations"; members = [ "system-access" ]; };
        server-access      = { scope = "system"; description = "Login access to servers"; members = [ "system-access" ]; };

        # Service access (kanidm oauth2)
        "grafana.access"        = { scope = "kanidm"; description = "Grafana login"; members = [ "users" ]; };
        "grafana.server-admins" = { scope = "kanidm"; description = "Grafana server admin"; members = [ "admins" ]; };
        "media.access"          = { scope = "kanidm"; description = "Jellyfin access"; members = [ "users" ]; };

        # Unix system groups
        wheel    = { scope = "unix"; description = "Sudo access"; members = []; };
        podman   = { scope = "unix"; description = "Container runtime"; members = []; };
        libvirtd = { scope = "unix"; description = "VM management"; members = []; };
        audio    = { scope = "unix"; description = "Audio device access"; members = []; };
        video    = { scope = "unix"; description = "Video device access"; members = []; };
        render   = { scope = "unix"; description = "GPU render access"; members = []; };
      };

      # ─── Environment access bindings ────────────────────────────────
      # environments.<env>.access = { user → [group] }

      environments = {
        prod = {
          access = {
            sini  = [ "admins" "system-access" "wheel" "podman" "libvirtd" "audio" "video" "render" ];
            shuo  = [ "users" "workstation-access" "wheel" "podman" "audio" "video" "render" ];
            will  = [ "users" "workstation-access" "wheel" "podman" "audio" "video" "render" ];
            json  = [ "admins" ];
            hugs  = [ "users" "grafana.server-admins" ];
            greco = [ "users" ];
          };
          system-access-groups = [ "system-access" ];
        };
        dev = {
          access = {
            sini = [ "admins" "system-access" "wheel" ];
          };
          system-access-groups = [ "system-access" ];
        };
      };

      # ─── Host definitions ──────────────────────────────────────────
      # hosts.<host> = { environment, role, system-access-groups }

      hosts = {
        cortex  = { environment = "prod"; role = "workstation"; system-access-groups = [ "workstation-access" ]; };
        blade   = { environment = "prod"; role = "workstation"; system-access-groups = [ "workstation-access" ]; };
        patch   = { environment = "prod"; role = "workstation"; system-access-groups = [ "system-access" ]; };
        axon-01 = { environment = "prod"; role = "server";      system-access-groups = [ "server-access" ]; };
        dev-box = { environment = "dev";  role = "dev";         system-access-groups = [ "workstation-access" ]; };
      };

      # ─── Build the scope graph ──────────────────────────────────────

      groupNames = builtins.attrNames groups;
      hostNames = builtins.attrNames hosts;
      envNames = builtins.attrNames environments;
      allUserNames = lib.unique (lib.concatMap
        (env: builtins.attrNames environments.${env}.access)
        envNames);

      baseNodes = engine.buildNodes {
        # Parent edges: hosts are children of their environment, envs are children of root
        parentGraph = engine.overlays (
          [ (engine.star "root" (map (e: "env:${e}") envNames)) ]
          ++ map (host:
            engine.edge "host:${host}" "env:${hosts.${host}.environment}"
          ) hostNames
        );

        # M edges: group-to-group membership (transitive)
        # "users" has members = ["admins"], meaning admins are members of users.
        # In scope graph terms: admins → users (admins can see users' scope).
        # Reversed: being a member of users means users' privileges flow TO members.
        # Model: M edge FROM the group TO each member group (member inherits parent's privileges)
        edgeGraphs = {
          # M edges for membership + isolated group vertices for groups with no edges
          M = engine.overlays (
            # Membership edges
            (lib.concatMap (gname:
              let g = groups.${gname};
              in map (member: engine.edge "group:${member}" "group:${gname}") g.members
            ) groupNames)
            # Ensure ALL groups exist as vertices even if they have no membership edges
            ++ [ (engine.vertices (map (g: "group:${g}") groupNames)) ]
          );
        };

        decls = lib.listToAttrs (
          # Root
          [{ name = "root"; value = {}; }]
          # Groups
          ++ map (gname: {
            name = "group:${gname}";
            value = {
              inherit (groups.${gname}) scope description;
              name = gname;
            };
          }) groupNames
          # Environments
          ++ map (ename: {
            name = "env:${ename}";
            value = {
              name = ename;
              inherit (environments.${ename}) system-access-groups;
              access = environments.${ename}.access;
            };
          }) envNames
          # Hosts
          ++ map (hname: {
            name = "host:${hname}";
            value = {
              name = hname;
              inherit (hosts.${hname}) role;
              system-access-groups = hosts.${hname}.system-access-groups;
            };
          }) hostNames
        );

        types = lib.listToAttrs (
          [{ name = "root"; value = "root"; }]
          ++ map (g: { name = "group:${g}"; value = "group"; }) groupNames
          ++ map (e: { name = "env:${e}"; value = "environment"; }) envNames
          ++ map (h: { name = "host:${h}"; value = "host"; }) hostNames
        );
      };

      # ─── Attributes ────────────────────────────────────────────────

      # Resolve all transitive group memberships for a group.
      # If you're in group X, you're also in everything X is a member of (via M edges).
      transitiveGroups = self: groupId:
        let
          direct = engine.followEdge "M" self groupId;
          transitive = lib.concatMap (gid: transitiveGroups self gid) direct;
        in lib.unique ([ groupId ] ++ direct ++ transitive);

      attributes = {
        # Merged system-access-groups for a host:
        # unique(env.system-access-groups ++ host.system-access-groups)
        effectiveGates = self: id:
          let
            node = self.nodes.${id};
            hostGates = node.decls.system-access-groups or [];
            envGates =
              if node.parent != null
              then self.nodes.${node.parent}.decls.system-access-groups or []
              else [];
          in lib.unique (envGates ++ hostGates);

        # For a given user on a given host, resolve full access.
        # Uses paramAttr: (self, hostId, userName) → resolved record.
        resolveUser = engine.paramAttr (self: hostId: userName:
          let
            hostNode = self.nodes.${hostId};
            envId = hostNode.parent;
            envAccess = self.nodes.${envId}.decls.access or {};
            directGroups = envAccess.${userName} or [];

            # Resolve transitive membership for each direct group
            allGroupIds = lib.unique (lib.concatMap
              (gname: transitiveGroups self "group:${gname}")
              directGroups);
            allGroupNames = map
              (gid: self.nodes.${gid}.decls.name)
              (builtins.filter (gid: self.nodes ? ${gid}) allGroupIds);

            # Partition by scope
            byScope = scope: builtins.filter
              (gid: (self.nodes.${gid}.decls.scope or "") == scope)
              allGroupIds;
            namesForScope = scope: map
              (gid: self.nodes.${gid}.decls.name)
              (byScope scope);

            systemGroups = namesForScope "system";
            unixGroups = namesForScope "unix";
            kanidmGroups = namesForScope "kanidm";

            # Login check: intersection of system-scoped groups with effective gates
            gates = self.evaluated.${hostId}.get "effectiveGates";
            gateGroupIds = map (g: "group:${g}") gates;
            systemGroupIds = byScope "system";
            gateIntersection = builtins.filter
              (gid: builtins.elem gid gateGroupIds)
              systemGroupIds;
            enable = gateIntersection != [];
          in {
            inherit userName enable;
            inherit directGroups;
            allGroups = builtins.sort builtins.lessThan allGroupNames;
            inherit systemGroups unixGroups kanidmGroups;
            effectiveGates = gates;
          }
        );
      };

      result = engine.eval { inherit baseNodes attributes; };

      # ─── Helper: resolve a user on a host ───────────────────────────
      resolveOn = host: user:
        result.evaluated."host:${host}".get "resolveUser" user;

    in
    {
      # ═══════════════════════════════════════════════════════════════
      # Test: sini on cortex (ACL.md example)
      #
      # direct groups    = [ "admins" "system-access" "wheel" ... ]
      # transitive       = [ "admins" "users" "system-access" "workstation-access"
      #                      "server-access" "grafana.access" "media.access" ... ]
      # merged gates     = [ "system-access" "workstation-access" ]
      # system-scoped    = [ "system-access" "workstation-access" "server-access" ]
      # intersection     = [ "system-access" ]  → enable = true
      # unix-scoped      = [ "wheel" "podman" "libvirtd" "audio" "video" "render" ]
      # ═══════════════════════════════════════════════════════════════

      tests.sini-on-cortex =
        let r = resolveOn "cortex" "sini";
        in {
          enable = r.enable;                    # → true
          unixGroups = builtins.sort builtins.lessThan r.unixGroups;
          # → [ "audio" "libvirtd" "podman" "render" "video" "wheel" ]
          has-system-access = builtins.elem "system-access" r.systemGroups;  # → true
        };

      # ═══════════════════════════════════════════════════════════════
      # Test: json on cortex (ACL.md example — identity-only, no login)
      #
      # direct groups = [ "admins" ]
      # transitive    = [ "admins" "users" "grafana.access" "media.access" ... ]
      # system-scoped = []  → no system groups
      # intersection  = []  → enable = false
      # ═══════════════════════════════════════════════════════════════

      tests.json-on-cortex =
        let r = resolveOn "cortex" "json";
        in {
          enable = r.enable;                    # → false (no system-access)
          unixGroups = r.unixGroups;             # → []
          systemGroups = r.systemGroups;          # → []
          has-kanidm = builtins.elem "admins" r.kanidmGroups;  # → true
        };

      # ─── Transitive membership ──────────────────────────────────────

      # admins is member of users (users.members = ["admins"])
      # users is member of grafana.access, media.access
      # So sini (who has admins) should transitively have users, grafana.access, media.access
      tests.sini-transitive-groups =
        let r = resolveOn "cortex" "sini";
        in {
          has-users = builtins.elem "users" r.allGroups;
          has-grafana = builtins.elem "grafana.access" r.allGroups;
          has-media = builtins.elem "media.access" r.allGroups;
        };

      # json has admins → transitively gets users, grafana.access, etc.
      tests.json-transitive =
        let r = resolveOn "cortex" "json";
        in {
          has-users = builtins.elem "users" r.allGroups;
          has-grafana = builtins.elem "grafana.access" r.allGroups;
        };

      # ─── Effective gates (env + host merge) ─────────────────────────

      tests.cortex-gates =
        result.evaluated."host:cortex".get "effectiveGates";
        # → [ "system-access" "workstation-access" ]

      tests.axon-gates =
        result.evaluated."host:axon-01".get "effectiveGates";
        # → [ "system-access" "server-access" ]

      tests.patch-gates =
        result.evaluated."host:patch".get "effectiveGates";
        # → [ "system-access" ] (patch only has system-access)

      # ─── shuo on cortex: workstation access ─────────────────────────

      tests.shuo-on-cortex =
        let r = resolveOn "cortex" "shuo";
        in {
          enable = r.enable;                    # → true (has workstation-access)
          unixGroups = builtins.sort builtins.lessThan r.unixGroups;
          has-workstation = builtins.elem "workstation-access" r.systemGroups;
        };

      # ─── shuo on axon-01: server, no workstation-access gate ────────

      tests.shuo-on-axon =
        let r = resolveOn "axon-01" "shuo";
        in {
          enable = r.enable;
          # shuo has workstation-access directly (system scope).
          # axon gates = [ "system-access" "server-access" ].
          # workstation-access NOT in axon gates → enable = false.
          # Having workstation-access does NOT transitively grant system-access —
          # the membership direction is: system-access members get workstation-access,
          # not the reverse.
        };

      # ─── greco: users only, no system access ───────────────────────

      tests.greco-on-cortex =
        let r = resolveOn "cortex" "greco";
        in {
          enable = r.enable;                    # → false
          kanidmGroups = builtins.sort builtins.lessThan r.kanidmGroups;
          # → [ "grafana.access" "media.access" "users" ]
        };

      # ─── hugs: users + grafana admin, no system access ─────────────

      tests.hugs-on-cortex =
        let r = resolveOn "cortex" "hugs";
        in {
          enable = r.enable;                    # → false
          has-grafana-admin = builtins.elem "grafana.server-admins" r.kanidmGroups;
        };

      # ─── Cross-environment: sini on dev-box ────────────────────────

      tests.sini-on-devbox =
        let r = resolveOn "dev-box" "sini";
        in {
          enable = r.enable;                    # → true
          unixGroups = r.unixGroups;             # → [ "wheel" ] (dev env has fewer)
        };

      # ─── Group graph structure ──────────────────────────────────────

      # Group membership edges (M)
      tests.admins-member-of =
        engine.followEdge "M" result "group:admins";
        # → [ "group:users" ] (admins is a member of users)

      tests.users-member-of =
        builtins.sort builtins.lessThan
          (engine.followEdge "M" result "group:users");
        # → [ "group:grafana.access" "group:media.access" ]

      tests.system-access-member-of =
        builtins.sort builtins.lessThan
          (engine.followEdge "M" result "group:system-access");
        # → [ "group:server-access" "group:workstation-access" ]
        # (system-access is listed as member of both)
        # Wait — the members field says workstation-access.members = ["system-access"]
        # meaning system-access is a member OF workstation-access.
        # So M edge: system-access → workstation-access.
        # But we modeled M as: member → group (member inherits group's privileges).
        # Actually we want: workstation-access inherits from system-access.
        # Let me re-check the edge direction.
        #
        # ACL.md: workstation-access.members = ["system-access"]
        # Meaning: if you have system-access, you're also in workstation-access.
        # So system-access → workstation-access (system-access members see workstation-access scope).
        #
        # We built: M edge FROM member TO group:
        #   edge "group:system-access" "group:workstation-access"
        # That means following M from system-access reaches workstation-access.
        # → Correct: system-access transitively includes workstation-access and server-access.

      # ─── Typed queries ──────────────────────────────────────────────

      tests.all-groups =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "group"));

      tests.all-hosts =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "host"));

      tests.all-environments =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "environment"));

      # ─── Host ancestry ──────────────────────────────────────────────

      tests.cortex-env =
        engine.parent result "host:cortex";
        # → "env:prod"

      tests.cortex-ancestors =
        engine.ancestors result "host:cortex";
        # → [ "env:prod" "root" ]

      tests.dev-box-ancestors =
        engine.ancestors result "host:dev-box";
        # → [ "env:dev" "root" ]

      tests.prod-hosts =
        builtins.sort builtins.lessThan (engine.childrenIds result "env:prod");
        # → [ "host:axon-01" "host:blade" "host:cortex" "host:patch" ]

      # ─── Scope filtering ───────────────────────────────────────────

      # Collect all kanidm-scoped groups
      tests.kanidm-groups =
        builtins.sort builtins.lessThan (
          engine.collect
            { filter = n: n.type == "group" && (n.decls.scope or "") == "kanidm"; }
            (self: id: [ self.nodes.${id}.decls.name ])
            result
        );
        # → [ "admins" "grafana.access" "grafana.server-admins" "media.access" "users" ]

      tests.unix-groups =
        builtins.sort builtins.lessThan (
          engine.collect
            { filter = n: n.type == "group" && (n.decls.scope or "") == "unix"; }
            (self: id: [ self.nodes.${id}.decls.name ])
            result
        );
        # → [ "audio" "libvirtd" "podman" "render" "video" "wheel" ]

      tests.system-groups =
        builtins.sort builtins.lessThan (
          engine.collect
            { filter = n: n.type == "group" && (n.decls.scope or "") == "system"; }
            (self: id: [ self.nodes.${id}.decls.name ])
            result
        );
        # → [ "server-access" "system-access" "workstation-access" ]
    };
}
