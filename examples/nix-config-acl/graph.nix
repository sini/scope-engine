# ACL scope graph construction.
#
# Three-level resolution (from docs/ACL.md):
#   groups                              <- shared definitions (kanidm, unix, system scopes)
#     |
#   environments.<env>.access           <- user -> [group] bindings per environment
#     |
#   env.system-access-groups            <- env-wide baseline login gates
#     + host.system-access-groups       <- host-specific login gates (merged with env)
#     |
#   resolved user                       <- enable + systemGroups derived from above
{
  genScope,
  lib,
  groups,
  environments,
  hosts,
}:
let
  groupNames = builtins.attrNames groups;
  hostNames = builtins.attrNames hosts;
  envNames = builtins.attrNames environments;

  roots = genScope.buildNodes {
    # Parent edges: hosts -> environments -> root
    parentGraph = genScope.overlays (
      [ (genScope.star "root" (map (e: "env:${e}") envNames)) ]
      ++ map (host: genScope.edge "host:${host}" "env:${hosts.${host}.environment}") hostNames
    );

    # M edges: group-to-group membership (transitive).
    # "users" has members = ["admins"], meaning admins are members of users.
    # M edge FROM member TO group: member inherits group's privileges.
    edgeGraphs = {
      M = genScope.overlays (
        (lib.concatMap (
          gname:
          let
            g = groups.${gname};
          in
          map (member: genScope.edge "group:${member}" "group:${gname}") g.members
        ) groupNames)
        # Ensure ALL groups exist as vertices even if they have no membership edges.
        ++ [ (genScope.vertices (map (g: "group:${g}") groupNames)) ]
      );
    };

    decls = lib.listToAttrs (
      [
        {
          name = "root";
          value = { };
        }
      ]
      ++ map (gname: {
        name = "group:${gname}";
        value = {
          inherit (groups.${gname}) scope description;
          name = gname;
        };
      }) groupNames
      ++ map (ename: {
        name = "env:${ename}";
        value = {
          name = ename;
          inherit (environments.${ename}) system-access-groups;
          access = environments.${ename}.access;
        };
      }) envNames
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
      [
        {
          name = "root";
          value = "root";
        }
      ]
      ++ map (g: {
        name = "group:${g}";
        value = "group";
      }) groupNames
      ++ map (e: {
        name = "env:${e}";
        value = "environment";
      }) envNames
      ++ map (h: {
        name = "host:${h}";
        value = "host";
      }) hostNames
    );
  };
in
{
  inherit roots;
}
