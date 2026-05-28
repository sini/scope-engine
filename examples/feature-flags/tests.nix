# Feature flag tests.
{
  engine,
  lib,
  result,
}:
{
  alice-dark-mode = result.get "user:alice" "flag" "dark-mode";
  alice-new-editor = result.get "user:alice" "flag" "new-editor";
  bob-new-editor = result.get "user:bob" "flag" "new-editor";
  carol-dark-mode = result.get "user:carol" "flag" "dark-mode";
  carol-new-editor = result.get "user:carol" "flag" "new-editor";
  dave-beta = result.get "user:dave" "flag" "beta-features";
  dave-dark-mode = result.get "user:dave" "flag" "dark-mode";
  alice-max-items = result.get "user:alice" "flag" "max-items";
  carol-max-items = result.get "user:carol" "flag" "max-items";

  alice-ai-assist = result.get "user:alice" "flagWithDeps" "ai-assist";
  bob-ai-assist-blocked = !(result.get "user:bob" "flag" "new-editor");

  alice-effective =
    let
      f = result.get "user:alice" "effectiveFlags";
    in
    {
      dark-mode = f.dark-mode;
      new-editor = f.new-editor;
      max-items = f.max-items;
      beta-features = f.beta-features;
    };
  dave-effective =
    let
      f = result.get "user:dave" "effectiveFlags";
    in
    {
      dark-mode = f.dark-mode;
      beta-features = f.beta-features;
    };

  alpha-override-count = result.get "project:alpha" "overrideCount";
  global-override-count = result.get "global" "overrideCount";

  rollout-exists = result.allNodes ? "rollout:org:widgets";
  no-rollout-acme = !(result.allNodes ? "rollout:org:acme");
  rollout-stage = (result.node "rollout:org:widgets").decls.stage;
  rollout-converged = result.get "global" "rolloutPct";

  all-users = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "user"));
  all-orgs = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "org"));
  rollout-nodes = builtins.attrNames (engine.nodesByType result "rollout");

  alice-path = engine.ancestors result "user:alice";
  acme-projects = builtins.sort builtins.lessThan (engine.childrenIds result "org:acme");
  alpha-users = builtins.sort builtins.lessThan (engine.childrenIds result "project:alpha");
  is-alice-under-acme = engine.isAncestor result "org:acme" "user:alice";
  is-dave-under-acme = engine.isAncestor result "org:acme" "user:dave";
}
