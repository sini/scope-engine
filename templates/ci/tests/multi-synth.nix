{ lib, engine, ... }:
let
  # Helper: build a single base node (buildNodes needs edges to discover vertices)
  mkBase = id: decls: {
    ${id} = {
      inherit id decls;
      parent = null;
      imports = [];
      type = null;
      childrenIds = [];
      edgesByLabel = {};
      rels = {};
    };
  };

  # Multi-iteration: base has "org", synth adds "team" when org exists,
  # then adds "member" when team exists. Converges in 2 iterations.
  multiResult = engine.eval {
    baseNodes = mkBase "org" { kind = "org"; };
    synthesize = { nodes, evaluated }:
      (if nodes ? org && !(nodes ? team) then
        mkBase "team" { kind = "team"; }
      else {})
      // (if nodes ? team && !(nodes ? member) then
        mkBase "member" { kind = "member"; }
      else {});
    attributes = {};
  };

  # Single-pass still works (backward compat)
  singleResult = engine.eval {
    baseNodes = mkBase "a" {};
    synthesize = { nodes, evaluated }: mkBase "b" {};
    attributes = {};
  };

  # Cannot overwrite base nodes (monotone-add)
  overwriteResult = engine.eval {
    baseNodes = mkBase "a" { x = 1; };
    synthesize = { nodes, evaluated }: mkBase "a" { x = 999; };
    attributes = {};
  };
in
{
  multi-synth.test-multi-iteration-converges = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames multiResult.nodes);
    expected = [ "member" "org" "team" ];
  };

  multi-synth.test-single-pass-still-works = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames singleResult.nodes);
    expected = [ "a" "b" ];
  };

  multi-synth.test-cannot-overwrite-base = {
    expr = overwriteResult.nodes.a.decls.x;
    expected = 1;
  };

  multi-synth.test-max-iter-throws = {
    expr = builtins.tryEval (builtins.deepSeq (engine.eval {
      baseNodes = mkBase "a" {};
      synthesize = { nodes, evaluated }:
        mkBase "new-${toString (builtins.length (builtins.attrNames nodes))}" {};
      attributes = {};
      maxSynthIter = 3;
    }).nodes true);
    expected = { success = false; value = false; };
  };
}
