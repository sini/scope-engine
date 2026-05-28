# Dependency resolver tests.
{
  engine,
  lib,
  result,
  roots,
  attributes,
}:
{
  app-direct-deps = result.get "app@1.0" "imports";
  app-all-deps = builtins.sort builtins.lessThan (result.get "app@1.0" "allDeps");
  app-dep-count = result.get "app@1.0" "depCount";
  app-dep-depth = result.get "app@1.0" "depDepth";
  json-dep-depth = result.get "lib-json@1.5" "depDepth";

  app-available-apis = builtins.sort builtins.lessThan (result.get "app@1.0" "availableAPIs");
  http-available-apis = builtins.sort builtins.lessThan (result.get "lib-http@2.3" "availableAPIs");
  tls-available-apis = result.get "lib-tls@1.2" "availableAPIs";

  app-dev-deps = engine.followEdge "D" result "app@1.0";
  logging-not-in-runtime-deps = !(builtins.elem "lib-logging@3.1" (result.get "app@1.0" "allDeps"));

  manifest-exists = result.allNodes ? "resolved:app@1.0";
  manifest-resolved-deps = builtins.sort builtins.lessThan (result.node "resolved:app@1.0")
  .decls.resolvedDeps;
  manifest-type = (result.node "resolved:app@1.0").type;

  json-version-conflict =
    let
      jsonVersions = engine.collect { filter = n: (n.decls.name or "") == "lib-json"; } (self: id: [
        (self.node id).decls.version
      ]) result;
    in
    builtins.sort builtins.lessThan jsonVersions;

  json-conflict-count =
    let
      jsonPkgs = engine.collect { filter = n: (n.decls.name or "") == "lib-json"; } (self: id: [
        id
      ]) result;
    in
    builtins.length jsonPkgs;

  all-libs = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "lib"));
  lib-count = builtins.length (builtins.attrNames (engine.nodesByType result "lib"));
  workspace-children = builtins.sort builtins.lessThan (engine.childrenIds result "workspace");
  json-siblings =
    let
      sibs = engine.siblings result "lib-json@1.5";
    in
    builtins.elem "lib-json@2.0" sibs;

  debug-works =
    let
      debugResult = engine.evalDebug {
        inherit roots attributes;
      };
    in
    debugResult.get "app@1.0" "depDepth";
}
