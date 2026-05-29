# Feature flag attributes.
{ genScope, lib }:
{
  flag = genScope.paramAttr (
    self: id: flagName:
    genScope.query {
      dataFilter = node: node.decls.${flagName} or null;
    } self id
  );

  effectiveFlags =
    self: id:
    let
      node = self.node id;
      parentFlags = if node.parent != null then self.get node.parent "effectiveFlags" else { };
    in
    genScope.shadow (builtins.removeAttrs node.decls [ "__edges" ]) parentFlags;

  flagWithDeps = genScope.paramAttr (
    self: id: flagName:
    let
      raw = self.get id "flag" flagName;
      deps = {
        ai-assist = [ "new-editor" ];
      };
      flagDeps = deps.${flagName} or [ ];
      allDepsMet = builtins.all (dep: self.get id "flag" dep == true) flagDeps;
    in
    if flagDeps == [ ] then raw else raw && allDepsMet
  );

  overrideCount =
    self: id:
    let
      effective = self.get id "effectiveFlags";
      defaults = (self.node "global").decls;
    in
    builtins.length (
      builtins.filter (key: key != "__edges" && effective.${key} != (defaults.${key} or null)) (
        builtins.filter (k: k != "__edges") (builtins.attrNames defaults)
      )
    );

  # Circular attribute: rollout convergence (Sloane 2010 §2.2).
  rolloutPct = genScope.circular { init = 0; } (
    self: id: prev:
    let
      target = 100;
    in
    if prev >= target then
      target
    else
      let
        next = prev + 25;
      in
      if next > target then target else next
  );
}
