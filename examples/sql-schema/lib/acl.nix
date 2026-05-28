# ACL synthesis — cross-model bridge between LDAP identity and infrastructure.
#
# Walks: user → ldap-role → access-policy → resource targets
# Two scopes:
#   direct:     user's assigned servers (or services on them, or LBs fronting those)
#   transitive: gen-graph reachableFrom to walk dependency graph
{
  lib,
  graphLib,
  instanceNodes,
}:
let
  # Bidirectional instance graph: union forward + reversed edges
  biInstanceNodes =
    let
      rev = graphLib.transpose instanceNodes;
    in
    {
      edges = id: (instanceNodes.edges id) ++ (rev.edges id);
      inherit (instanceNodes) nodes parent nodeData;
    };

  synthesizeAccess =
    rawFleet:
    let
      users = rawFleet.user or { };
      policies = rawFleet.access-policy or { };
      services = rawFleet.service or { };
      backends = rawFleet.backend or { };

      # For each user, find matching policies and resolve targets
      userEntries = builtins.concatMap (
        userName:
        let
          user = users.${userName};
          userRole = user.ldap-role;
          userServers = user.servers or [ ];

          # Policies matching this user's role
          matchingPolicies = lib.filterAttrs (_: p: p.ldap-role == userRole) policies;

          # Resolve targets for a policy
          policyEntries = lib.concatMap (
            policyName:
            let
              policy = matchingPolicies.${policyName};
              targets =
                if policy.scope == "direct" then
                  directTargets policy userServers
                else
                  transitiveTargets policy userServers;
            in
            map (target: {
              name = "${userName}:${target}";
              value = {
                user = userName;
                resource = target;
                inherit (policy) actions;
                via = "access-policy:${policyName}";
              };
            }) targets
          ) (builtins.attrNames matchingPolicies);
        in
        policyEntries
      ) (builtins.attrNames users);

      # Direct scope: user's assigned servers, or services/LBs on those servers
      directTargets =
        policy: serverList:
        if policy.resource-kind == "server" then
          map (s: "server:${s}") serverList
        else if policy.resource-kind == "service" then
          # Services running on user's assigned servers
          let
            serverSet = serverList;
            matchingServices = lib.filterAttrs (_: svc: builtins.elem (svc.server or "") serverSet) services;
          in
          map (s: "service:${s}") (builtins.attrNames matchingServices)
        else if policy.resource-kind == "loadbalancer" then
          # LBs fronting services on user's assigned servers
          let
            serverServices = builtins.filter (
              svcName: builtins.elem (services.${svcName}.server or "") serverList
            ) (builtins.attrNames services);
            matchingBackends = lib.filterAttrs (_: b: builtins.elem (b.service or "") serverServices) backends;
            lbNames = lib.unique (map (b: b.loadbalancer or "") (builtins.attrValues matchingBackends));
          in
          map (lb: "loadbalancer:${lb}") (builtins.filter (n: n != "") lbNames)
        else
          [ ];

      # Transitive scope: walk from user's servers through service dependencies
      transitiveTargets =
        policy: serverList:
        if policy.resource-kind == "service" then
          # Services on assigned servers + services reachable via dependencies
          let
            onServerServices = builtins.filter (
              svcName: builtins.elem (services.${svcName}.server or "") serverList
            ) (builtins.attrNames services);
            # Walk service dependencies via bidirectional instance graph
            reachable = builtins.concatMap (
              svc: graphLib.reachableFrom biInstanceNodes "service:${svc}"
            ) onServerServices;
            reachableServices = lib.unique (
              onServerServices
              ++ map (id: lib.removePrefix "service:" id) (
                builtins.filter (id: lib.hasPrefix "service:" id) reachable
              )
            );
          in
          map (s: "service:${s}") reachableServices
        else if policy.resource-kind == "loadbalancer" then
          # LBs reachable from assigned servers' services
          let
            onServerServices = builtins.filter (
              svcName: builtins.elem (services.${svcName}.server or "") serverList
            ) (builtins.attrNames services);
            matchingBackends = lib.filterAttrs (
              _: b: builtins.elem (b.service or "") onServerServices
            ) backends;
            lbNames = lib.unique (map (b: b.loadbalancer or "") (builtins.attrValues matchingBackends));
          in
          map (lb: "loadbalancer:${lb}") (builtins.filter (n: n != "") lbNames)
        else
          directTargets policy serverList;

    in
    builtins.listToAttrs userEntries;
in
{
  inherit synthesizeAccess;
}
