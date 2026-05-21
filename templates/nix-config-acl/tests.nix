# ACL tests — validates resolution examples from docs/ACL.md.
{ engine, lib, result, resolveOn }:
{
  sini-on-cortex = let r = resolveOn "cortex" "sini"; in {
    enable = r.enable;
    unixGroups = builtins.sort builtins.lessThan r.unixGroups;
    has-system-access = builtins.elem "system-access" r.systemGroups;
  };

  json-on-cortex = let r = resolveOn "cortex" "json"; in {
    enable = r.enable; unixGroups = r.unixGroups;
    systemGroups = r.systemGroups;
    has-kanidm = builtins.elem "admins" r.kanidmGroups;
  };

  sini-transitive-groups = let r = resolveOn "cortex" "sini"; in {
    has-users = builtins.elem "users" r.allGroups;
    has-grafana = builtins.elem "grafana.access" r.allGroups;
    has-media = builtins.elem "media.access" r.allGroups;
  };

  json-transitive = let r = resolveOn "cortex" "json"; in {
    has-users = builtins.elem "users" r.allGroups;
    has-grafana = builtins.elem "grafana.access" r.allGroups;
  };

  cortex-gates = result.evaluated."host:cortex".get "effectiveGates";
  axon-gates = result.evaluated."host:axon-01".get "effectiveGates";
  patch-gates = result.evaluated."host:patch".get "effectiveGates";

  shuo-on-cortex = let r = resolveOn "cortex" "shuo"; in {
    enable = r.enable;
    unixGroups = builtins.sort builtins.lessThan r.unixGroups;
    has-workstation = builtins.elem "workstation-access" r.systemGroups;
  };

  shuo-on-axon = let r = resolveOn "axon-01" "shuo"; in { enable = r.enable; };

  greco-on-cortex = let r = resolveOn "cortex" "greco"; in {
    enable = r.enable;
    kanidmGroups = builtins.sort builtins.lessThan r.kanidmGroups;
  };

  hugs-on-cortex = let r = resolveOn "cortex" "hugs"; in {
    enable = r.enable;
    has-grafana-admin = builtins.elem "grafana.server-admins" r.kanidmGroups;
  };

  sini-on-devbox = let r = resolveOn "dev-box" "sini"; in {
    enable = r.enable; unixGroups = r.unixGroups;
  };

  admins-member-of = engine.followEdge "M" result "group:admins";
  users-member-of = builtins.sort builtins.lessThan (engine.followEdge "M" result "group:users");
  system-access-member-of = builtins.sort builtins.lessThan (engine.followEdge "M" result "group:system-access");

  all-groups = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "group"));
  all-hosts = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "host"));
  all-environments = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "environment"));

  cortex-env = engine.parent result "host:cortex";
  cortex-ancestors = engine.ancestors result "host:cortex";
  dev-box-ancestors = engine.ancestors result "host:dev-box";
  prod-hosts = builtins.sort builtins.lessThan (engine.childrenIds result "env:prod");

  kanidm-groups = builtins.sort builtins.lessThan (
    engine.collect { filter = n: n.type == "group" && (n.decls.scope or "") == "kanidm"; }
      (self: id: [ self.nodes.${id}.decls.name ]) result);
  unix-groups = builtins.sort builtins.lessThan (
    engine.collect { filter = n: n.type == "group" && (n.decls.scope or "") == "unix"; }
      (self: id: [ self.nodes.${id}.decls.name ]) result);
  system-groups = builtins.sort builtins.lessThan (
    engine.collect { filter = n: n.type == "group" && (n.decls.scope or "") == "system"; }
      (self: id: [ self.nodes.${id}.decls.name ]) result);
}
