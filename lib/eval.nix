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
      maxSynthIter ? 10,
    }:
    lib.fix (
      self:
      let
        # Synthesize sees all current nodes + evaluated for attribute access.
        # Convergence loop: iterate until no new nodes are produced (Vogt 1989).
        # synthesize MUST NOT read evaluated attributes of nodes it creates in
        # the same or later iteration — only base/previously-converged nodes.
        synthesized =
          let
            go = n: prevSynth:
              if n >= maxSynthIter then
                throw "gen-scope: synthesis exceeded ${toString maxSynthIter} iterations (Vogt well-definedness)"
              else
                let
                  allNodes = baseNodes // prevSynth;
                  input = { nodes = allNodes; inherit (self) evaluated; };
                  newSynth = builtins.removeAttrs (synthesize input) (builtins.attrNames allNodes);
                in
                if newSynth == {} then prevSynth
                else go (n + 1) (prevSynth // newSynth);
          in
          go 0 {};
      in
      {
        # Synthesized nodes add to the graph; cannot overwrite base nodes.
        # Enforces the HOAG monotone-add invariant (Vogt et al., 1989).
        nodes = baseNodes // synthesized;
        evaluated = lib.mapAttrs (
          id: _node: {
            get =
              attrName:
              if attributes ? ${attrName} then
                builtins.addErrorContext "evaluating attribute '${attrName}' on scope '${id}'" (
                  attributes.${attrName} self id
                )
              else
                throw "gen-scope: unknown attribute '${attrName}' on node '${id}'";
          }
        ) self.nodes;
      }
    );

  # Diagnostic variant with shadow-stack cycle tracing (spec Open Question #2/#5).
  #
  # Threads a _visited list through self so that cycles produce structured
  # traces like "gen-scope: cycle: a.x -> b.x -> a.x" instead of Nix's
  # opaque "infinite recursion encountered."
  #
  # Attribute functions keep the same signature (self: id:). The visited
  # stack lives on self._visited and is updated transparently by get.
  #
  # Trade-off: defeats Nix's native memoization — every get call creates a
  # new self with a longer _visited list, so the same (id, attrName) pair
  # may be evaluated multiple times along different call paths. List-based
  # _visited is intentional here: ordered traces need sequence, and perf
  # is already sacrificed for diagnostics. Use eval for production.
  evalDebug =
    {
      baseNodes,
      synthesize ? (_: { }),
      attributes,
    }:
    let
      maxSynthIter = 10;
      synthesized =
        let
          go = n: prevSynth:
            if n >= maxSynthIter then
              throw "gen-scope: synthesis exceeded ${toString maxSynthIter} iterations (Vogt well-definedness)"
            else
              let
                allNodes = baseNodes // prevSynth;
                input = { nodes = allNodes; evaluated = result.evaluated; };
                newSynth = builtins.removeAttrs (synthesize input) (builtins.attrNames allNodes);
              in
              if newSynth == {} then prevSynth
              else go (n + 1) (prevSynth // newSynth);
        in
        go 0 {};
      nodes = baseNodes // synthesized;

      mkEvaluated =
        visited:
        lib.mapAttrs (
          id: _node: {
            get =
              attrName:
              let
                traceEntry = "${id}.${attrName}";
              in
              if !(attributes ? ${attrName}) then
                throw "gen-scope: unknown attribute '${attrName}' on node '${id}'"
              else if builtins.elem traceEntry visited then
                throw "gen-scope: cycle detected: ${builtins.concatStringsSep " -> " (visited ++ [ traceEntry ])}"
              else
                let
                  # Create a new self with the updated visited stack.
                  selfWithTrace = {
                    inherit nodes;
                    _visited = visited ++ [ traceEntry ];
                    evaluated = mkEvaluated (visited ++ [ traceEntry ]);
                  };
                in
                attributes.${attrName} selfWithTrace id;
          }
        ) nodes;

      result = {
        inherit nodes;
        _visited = [ ];
        evaluated = mkEvaluated [ ];
      };
    in
    result;
in
{
  inherit eval evalDebug;
}
