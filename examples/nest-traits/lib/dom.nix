{ lib, engine }:
let
  mkPath = prefix: key: if prefix == "" then key else "${prefix}.${key}";

  walkDom = dom: walkDomRec "" null { } dom;

  walkDomRec =
    pathPrefix: parentPath: inheritedAttrs: attrset:
    builtins.foldl' (
      acc: key:
      let
        val = attrset.${key};
        path = mkPath pathPrefix key;
      in
      if !builtins.isAttrs val then
        acc
      else if val ? is && builtins.isList val.is then
        let
          node =
            inheritedAttrs
            // val
            // {
              name = key;
              __path = path;
              __parentPath = parentPath;
            };
          children = walkDomRec path path inheritedAttrs val;
        in
        acc ++ [ node ] ++ children
      else
        let
          nsAttrs = builtins.listToAttrs (
            builtins.filter (x: !builtins.isAttrs x.value) (
              map (k: {
                name = k;
                value = val.${k};
              }) (builtins.attrNames val)
            )
          );
          merged = inheritedAttrs // nsAttrs;
        in
        acc ++ walkDomRec path parentPath merged val
    ) [ ] (builtins.attrNames attrset);

  buildDomGraph =
    nodes:
    let
      nodeIds = map (n: n.__path) nodes;
      parentEdges = builtins.filter (e: e != null) (
        map (n: if n.__parentPath != null then engine.edge n.__path n.__parentPath else null) nodes
      );
    in
    engine.buildNodes {
      parentGraph = engine.overlays ([ (engine.vertices nodeIds) ] ++ parentEdges);
      decls = builtins.listToAttrs (
        map (n: {
          name = n.__path;
          value = builtins.removeAttrs n [
            "__path"
            "__parentPath"
            "__mergedCfg"
          ];
        }) nodes
      );
    };
in
{
  inherit walkDom buildDomGraph;
}
