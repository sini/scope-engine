# Rule-based NixOS configuration engine — gen-derive edition.
# Replaces the hand-rolled rule dispatch with gen-derive's stratified dispatch
# and fixpoint convergence. Rules use gen-select selectors as conditions.
#
# Two phases:
#   structural — enrich actions feed back into context (fixpoint converges)
#   config     — nixos actions collect NixOS module fragments
{
  lib,
  deriveLib,
  selectLib,
}:
let
  inherit (deriveLib)
    mkRule
    fixpoint
    entryAnywhere
    entryAfter
    mkActions
    ;
  match = deriveLib.adapters.select.mkMatch selectLib;

  # Action vocabulary: two phases
  fx = mkActions {
    structural = [ "enrich" ];
    config = [ "nixos" ];
  };

  # Phase DAG: structural fires first, config fires after
  phases = {
    structural = entryAnywhere { };
    config = entryAfter [ "structural" ] { };
  };

  # Bridge server data to gen-select's five-field accessor context
  mkServerContext = serverData: {
    data = _id: serverData;
    parent = _: null;
    children = _: [ ];
    ancestors = _: [ ];
    siblings = _: [ ];
  };

  # Extract enrich actions as context feedback for fixpoint
  extract =
    actions:
    lib.foldl' (acc: a: if a.__action == "enrich" then acc // { ${a.key} = a.value; } else acc) { } (
      actions.structural or [ ]
    );

  # Dispatch rules for a server via gen-derive fixpoint, return merged NixOS config
  buildHostConfig =
    fleet: rules: serverName:
    let
      server = fleet.server.${serverName};
      serverData = server // {
        tags = server.tags or [ ];
        environment =
          if builtins.isAttrs (server.environment or null) then
            server.environment.tier or "unknown"
          else
            server.environment or "unknown";
      };
      result = fixpoint {
        inherit
          rules
          phases
          match
          extract
          ;
        id = serverName;
        context = mkServerContext serverData;
        classify = fx.classify;
        combine = ctx: ext: {
          data = _id: (ctx.data _id) // ext;
          inherit (ctx)
            parent
            children
            ancestors
            siblings
            ;
        };
        eq = a: b: (a.data serverName) == (b.data serverName);
      };
      nixosActions = result.actions.config or [ ];
    in
    lib.foldl' lib.recursiveUpdate { } (map (a: builtins.removeAttrs a [ "__action" ]) nixosActions);

  # Build all host configs: { serverName = mergedConfig; }
  buildAllHostConfigs =
    fleet: rules: lib.mapAttrs (name: _: buildHostConfig fleet rules name) (fleet.server or { });
in
{
  inherit
    fx
    phases
    match
    mkServerContext
    extract
    buildHostConfig
    buildAllHostConfigs
    ;
}
