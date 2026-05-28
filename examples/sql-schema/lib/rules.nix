# Rule-based NixOS configuration engine.
# Rules match servers via SQL WHERE clauses and deliver NixOS module fragments.
# Parallels nest-traits' CSS selector → config delivery:
#   nest:  { is = traits.host; nixos = { ... }; }
#   sql:   { where = "tags IN ('web')"; nixos = { ... }; }
#
# The engine evaluates each rule's WHERE against each server, collects matching
# modules, and deep-merges them into per-server NixOS configurations.
{ lib, queryFn }:
# queryFn: fleet → sqlString → results (the query function from engine.nix)
let
  inherit (builtins)
    any
    filter
    isFunction
    length
    ;
  inherit (lib) concatMap foldl' mapAttrs;

  # Match a rule against a specific server.
  # Three matching modes:
  #   1. No `where` or `match` → matches all servers
  #   2. `where` (string) → SQL WHERE clause evaluated against the servers table
  #   3. `match` (function) → Nix predicate: { fleet, serverName, server } → bool
  ruleMatchesServer =
    fleet: rule: serverName:
    let
      whereClause = rule.where or null;
      matchFn = rule.match or null;
    in
    if matchFn != null then
      matchFn {
        inherit fleet serverName;
        server = fleet.server.${serverName};
      }
    else if whereClause == null then
      true # no WHERE = matches all servers
    else
      let
        # Support both WHERE fragments and full SELECT queries.
        # If the clause starts with SELECT, run it as-is; otherwise wrap it.
        trimmed = lib.trimWith {
          start = true;
          end = true;
        } whereClause;
        isFullQuery = lib.hasPrefix "SELECT" (lib.toUpper (lib.substring 0 6 trimmed));
        sqlQuery = if isFullQuery then trimmed else "SELECT name FROM servers WHERE ${whereClause}";
        results = queryFn fleet sqlQuery;
      in
      any (r: (r.name or r) == serverName) results;

  # Collect all rule modules that match a server
  matchingModules =
    fleet: rules: serverName:
    let
      matches = filter (r: ruleMatchesServer fleet r serverName) rules;
    in
    concatMap (
      r:
      let
        nixosCfg = r.nixos or { };
      in
      if isFunction nixosCfg then
        [
          (nixosCfg {
            inherit fleet serverName;
            server = fleet.server.${serverName};
          })
        ]
      else
        [ nixosCfg ]
    ) matches;

  # Build a complete NixOS config for a server from matching rules.
  # Deep-merges the base module (from nixos.nix buildServerModule) with all
  # matching rule modules, in rule declaration order.
  buildHostConfig =
    fleet: rules: baseModuleFn: serverName:
    let
      base = baseModuleFn fleet serverName;
      ruleModules = matchingModules fleet rules serverName;
    in
    foldl' lib.recursiveUpdate base ruleModules;

  # Build all host configs: { serverName = mergedConfig; }
  buildAllHostConfigs =
    fleet: rules: baseModuleFn:
    mapAttrs (name: _: buildHostConfig fleet rules baseModuleFn name) (fleet.server or { });
in
{
  inherit
    ruleMatchesServer
    matchingModules
    buildHostConfig
    buildAllHostConfigs
    ;
}
