# ACL synthesis — cross-model bridge between LDAP identity and infrastructure.
#
# Walks: user → ldap-role → access-policy → resource targets
# Two scopes:
#   direct:     user's assigned servers (or services on them, or LBs fronting those)
#   transitive: gen-graph reachableFrom to walk dependency graph
{ lib }:
let
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
            # Walk service dependencies
            deps = rawFleet.service-dependency or { };
            walkDeps =
              visited: queue:
              if queue == [ ] then
                visited
              else
                let
                  current = builtins.head queue;
                  rest = builtins.tail queue;
                  # Find dependencies where current is downstream
                  upstreams = lib.mapAttrsToList (_: d: d.upstream) (
                    lib.filterAttrs (_: d: d.downstream == current && !(builtins.elem d.upstream visited)) deps
                  );
                  # Find dependencies where current is upstream
                  downstreams = lib.mapAttrsToList (_: d: d.downstream) (
                    lib.filterAttrs (_: d: d.upstream == current && !(builtins.elem d.downstream visited)) deps
                  );
                  newServices = upstreams ++ downstreams;
                in
                walkDeps (visited ++ newServices) (rest ++ newServices);
            reachableServices = lib.unique (onServerServices ++ walkDeps onServerServices onServerServices);
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
