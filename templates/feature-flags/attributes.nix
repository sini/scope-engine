# Feature flag attributes.
{ engine, lib }:
{
  flag = engine.paramAttr (self: id: flagName:
    engine.query {
      dataFilter = node: node.decls.${flagName} or null;
    } self id);

  effectiveFlags = self: id:
    let
      node = self.nodes.${id};
      parentFlags = if node.parent != null then self.evaluated.${node.parent}.get "effectiveFlags" else { };
    in engine.shadow node.decls parentFlags;

  flagWithDeps = engine.paramAttr (self: id: flagName:
    let
      raw = self.evaluated.${id}.get "flag" flagName;
      deps = { ai-assist = [ "new-editor" ]; };
      flagDeps = deps.${flagName} or [ ];
      allDepsMet = builtins.all (dep: self.evaluated.${id}.get "flag" dep == true) flagDeps;
    in if flagDeps == [ ] then raw else raw && allDepsMet);

  overrideCount = self: id:
    let
      effective = self.evaluated.${id}.get "effectiveFlags";
      defaults = self.nodes.global.decls;
    in builtins.length (builtins.filter (key:
      effective.${key} != (defaults.${key} or null)
    ) (builtins.attrNames defaults));

  # Circular attribute: rollout convergence (Sloane 2010 §2.2).
  rolloutPct = engine.circular { init = 0; } (
    self: id: prev:
    let target = 100;
    in if prev >= target then target
       else let next = prev + 25; in if next > target then target else next);
}
