# Config cascade attributes.
{
  engine,
  lib,
  roots,
}:
{
  children = _self: id: lib.filterAttrs (_: n: n.parent == id) roots;
  imports = _self: id: (_self.node id).decls.__edges.I or [ ];

  config = engine.paramAttr (
    self: id: key:
    engine.query { dataFilter = node: node.decls.${key} or null; } self id
  );

  resolvedConfig =
    self: id:
    let
      node = self.node id;
      local = builtins.removeAttrs node.decls [ "__edges" ];
      importIds = self.get id "imports";
      importedConfigs = lib.foldl' (
        acc: iid: engine.shadow (self.get iid "resolvedConfig") acc
      ) { } importIds;
      parentConfig = if node.parent != null then self.get node.parent "resolvedConfig" else { };
    in
    engine.shadow local (engine.shadow importedConfigs parentConfig);

  overriddenKeys =
    self: id:
    let
      allResults = key: engine.queryAll { dataFilter = node: node.decls.${key} or null; } self id;
      localKeys = builtins.filter (k: k != "__edges") (builtins.attrNames (self.node id).decls);
    in
    builtins.filter (key: builtins.length (allResults key) > 1) localKeys;

  configSources =
    self: id:
    let
      resolved = self.get id "resolvedConfig";
    in
    lib.mapAttrs (
      key: _:
      let
        node = self.node id;
        isLocal = node.decls ? ${key};
        importIds = self.get id "imports";
        isImported = builtins.any (iid: (self.get iid "resolvedConfig") ? ${key}) importIds;
      in
      if isLocal then
        "local"
      else if isImported then
        "import"
      else
        "inherited"
    ) resolved;
}
