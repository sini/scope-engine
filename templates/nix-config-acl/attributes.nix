# ACL resolution attributes.
{ engine, lib }:
let
  # Resolve all transitive group memberships for a group.
  # If you're in group X, you're also in everything X is a member of (via M edges).
  transitiveGroups =
    self: groupId:
    let
      direct = engine.followEdge "M" self groupId;
      transitive = lib.concatMap (gid: transitiveGroups self gid) direct;
    in
    lib.unique ([ groupId ] ++ direct ++ transitive);
in
{
  attributes = {
    # Merged system-access-groups for a host:
    # unique(env.system-access-groups ++ host.system-access-groups)
    # Cannot use inherit' here because we MERGE levels, not shadow.
    effectiveGates =
      self: id:
      let
        node = self.nodes.${id};
        hostGates = node.decls.system-access-groups or [ ];
        envGates =
          if node.parent != null then
            self.nodes.${node.parent}.decls.system-access-groups or [ ]
          else
            [ ];
      in
      lib.unique (envGates ++ hostGates);

    # For a given user on a given host, resolve full access.
    resolveUser = engine.paramAttr (
      self: hostId: userName:
      let
        hostNode = self.nodes.${hostId};
        envId = hostNode.parent;
        envAccess = self.nodes.${envId}.decls.access or { };
        directGroups = envAccess.${userName} or [ ];

        allGroupIds = lib.unique (
          lib.concatMap (gname: transitiveGroups self "group:${gname}") directGroups
        );
        allGroupNames = map (gid: self.nodes.${gid}.decls.name)
          (builtins.filter (gid: self.nodes ? ${gid}) allGroupIds);

        byScope = scope:
          builtins.filter (gid: (self.nodes.${gid}.decls.scope or "") == scope) allGroupIds;
        namesForScope = scope: map (gid: self.nodes.${gid}.decls.name) (byScope scope);

        systemGroups = namesForScope "system";
        unixGroups = namesForScope "unix";
        kanidmGroups = namesForScope "kanidm";

        gates = self.evaluated.${hostId}.get "effectiveGates";
        gateGroupIds = map (g: "group:${g}") gates;
        gateIntersection = builtins.filter (gid: builtins.elem gid gateGroupIds) (byScope "system");
        enable = gateIntersection != [ ];
      in
      {
        inherit userName enable directGroups;
        allGroups = builtins.sort builtins.lessThan allGroupNames;
        inherit systemGroups unixGroups kanidmGroups;
        effectiveGates = gates;
      }
    );
  };
}
