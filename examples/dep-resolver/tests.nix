# Dependency resolver tests.
{ engine, lib, result, baseNodes, attributes }:
{
  app-direct-deps = result.nodes."app@1.0".imports;
  app-all-deps = builtins.sort builtins.lessThan (result.evaluated."app@1.0".get "allDeps");
  app-dep-count = result.evaluated."app@1.0".get "depCount";
  app-dep-depth = result.evaluated."app@1.0".get "depDepth";
  json-dep-depth = result.evaluated."lib-json@1.5".get "depDepth";

  app-available-apis = builtins.sort builtins.lessThan (result.evaluated."app@1.0".get "availableAPIs");
  http-available-apis = builtins.sort builtins.lessThan (result.evaluated."lib-http@2.3".get "availableAPIs");
  tls-available-apis = result.evaluated."lib-tls@1.2".get "availableAPIs";

  app-dev-deps = engine.followEdge "D" result "app@1.0";
  logging-not-in-runtime-deps = !(builtins.elem "lib-logging@3.1" (result.evaluated."app@1.0".get "allDeps"));

  manifest-exists = result.nodes ? "resolved:app@1.0";
  manifest-resolved-deps = builtins.sort builtins.lessThan result.nodes."resolved:app@1.0".decls.resolvedDeps;
  manifest-type = result.nodes."resolved:app@1.0".type;

  json-version-conflict =
    let jsonVersions = engine.collect { filter = n: (n.decls.name or "") == "lib-json"; }
      (self: id: [ self.nodes.${id}.decls.version ]) result;
    in builtins.sort builtins.lessThan jsonVersions;

  json-conflict-count =
    let jsonPkgs = engine.collect { filter = n: (n.decls.name or "") == "lib-json"; }
      (self: id: [ id ]) result;
    in builtins.length jsonPkgs;

  all-libs = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "lib"));
  lib-count = builtins.length (builtins.attrNames (engine.nodesByType result "lib"));
  workspace-children = builtins.sort builtins.lessThan (engine.childrenIds result "workspace");
  json-siblings = let sibs = engine.siblings result "lib-json@1.5"; in builtins.elem "lib-json@2.0" sibs;

  debug-works =
    let debugResult = engine.evalDebug { inherit baseNodes attributes; };
    in debugResult.evaluated."app@1.0".get "depDepth";
}
