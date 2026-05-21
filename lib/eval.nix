# HOAG evaluator.
#
# Demand-driven evaluation via lib.fix. Nix's native lazy evaluation provides
# the scheduling, memoization, and cycle detection (Mokhov et al., 2018).
# builtins.addErrorContext on every get call provides breadcrumbs for cycle errors.
{ lib }:
let
  eval =
    {
      baseNodes,
      synthesize ? (_: { }),
      attributes,
    }:
    lib.fix (self:
    let
      # Synthesize sees baseNodes for structural inspection + evaluated for
      # attribute access. Cannot see its own output (monotone-add, not fixpoint).
      synthInput = { inherit (self) evaluated; nodes = baseNodes; };
      synthesized = builtins.removeAttrs (synthesize synthInput) (builtins.attrNames baseNodes);
    in
    {
      # Synthesized nodes add to the graph; cannot overwrite base nodes.
      # Enforces the HOAG monotone-add invariant (Vogt et al., 1989).
      nodes = baseNodes // synthesized;
      evaluated = lib.mapAttrs (
        id: _node:
        {
          get =
            attrName:
            if attributes ? ${attrName} then
              builtins.addErrorContext "evaluating attribute '${attrName}' on scope '${id}'" (
                attributes.${attrName} self id
              )
            else
              throw "scope-engine: unknown attribute '${attrName}' on node '${id}'";
        }
      ) self.nodes;
    });
in
{
  inherit eval;
}
