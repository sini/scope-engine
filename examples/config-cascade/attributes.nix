# Config cascade attributes.
{ engine, lib }:
{
  config = engine.paramAttr (
    self: id: key:
    engine.query { dataFilter = node: node.decls.${key} or null; } self id
  );

  resolvedConfig =
    self: id:
    let
      node = self.nodes.${id};
      local = node.decls;
      importedConfigs = lib.foldl' (
        acc: iid: engine.shadow (self.evaluated.${iid}.get "resolvedConfig") acc
      ) { } node.imports;
      parentConfig =
        if node.parent != null then self.evaluated.${node.parent}.get "resolvedConfig" else { };
    in
    engine.shadow local (engine.shadow importedConfigs parentConfig);

  overriddenKeys =
    self: id:
    let
      allResults = key: engine.queryAll { dataFilter = node: node.decls.${key} or null; } self id;
      localKeys = builtins.attrNames self.nodes.${id}.decls;
    in
    builtins.filter (key: builtins.length (allResults key) > 1) localKeys;

  configSources =
    self: id:
    let
      resolved = self.evaluated.${id}.get "resolvedConfig";
    in
    lib.mapAttrs (
      key: _:
      let
        node = self.nodes.${id};
        isLocal = node.decls ? ${key};
        isImported = builtins.any (iid: (self.evaluated.${iid}.get "resolvedConfig") ? ${key}) node.imports;
      in
      if isLocal then
        "local"
      else if isImported then
        "import"
      else
        "inherited"
    ) resolved;
}
