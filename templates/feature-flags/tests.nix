# Feature flag tests.
{ engine, lib, result }:
{
  alice-dark-mode = result.evaluated."user:alice".get "flag" "dark-mode";
  alice-new-editor = result.evaluated."user:alice".get "flag" "new-editor";
  bob-new-editor = result.evaluated."user:bob".get "flag" "new-editor";
  carol-dark-mode = result.evaluated."user:carol".get "flag" "dark-mode";
  carol-new-editor = result.evaluated."user:carol".get "flag" "new-editor";
  dave-beta = result.evaluated."user:dave".get "flag" "beta-features";
  dave-dark-mode = result.evaluated."user:dave".get "flag" "dark-mode";
  alice-max-items = result.evaluated."user:alice".get "flag" "max-items";
  carol-max-items = result.evaluated."user:carol".get "flag" "max-items";

  alice-ai-assist = result.evaluated."user:alice".get "flagWithDeps" "ai-assist";
  bob-ai-assist-blocked = !(result.evaluated."user:bob".get "flag" "new-editor");

  alice-effective = let f = result.evaluated."user:alice".get "effectiveFlags"; in {
    dark-mode = f.dark-mode; new-editor = f.new-editor;
    max-items = f.max-items; beta-features = f.beta-features;
  };
  dave-effective = let f = result.evaluated."user:dave".get "effectiveFlags"; in {
    dark-mode = f.dark-mode; beta-features = f.beta-features;
  };

  alpha-override-count = result.evaluated."project:alpha".get "overrideCount";
  global-override-count = result.evaluated.global.get "overrideCount";

  rollout-exists = result.nodes ? "rollout:org:widgets";
  no-rollout-acme = !(result.nodes ? "rollout:org:acme");
  rollout-stage = result.nodes."rollout:org:widgets".decls.stage;
  rollout-converged = result.evaluated.global.get "rolloutPct";

  all-users = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "user"));
  all-orgs = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "org"));
  rollout-nodes = builtins.attrNames (engine.nodesByType result "rollout");

  alice-path = engine.ancestors result "user:alice";
  acme-projects = builtins.sort builtins.lessThan (engine.childrenIds result "org:acme");
  alpha-users = builtins.sort builtins.lessThan (engine.childrenIds result "project:alpha");
  is-alice-under-acme = engine.isAncestor result "org:acme" "user:alice";
  is-dave-under-acme = engine.isAncestor result "org:acme" "user:dave";
}
