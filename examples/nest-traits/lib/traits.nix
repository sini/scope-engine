{
  lib,
  genScope,
  selectorsLib,
}:
let
  inherit (selectorsLib) matchesOne mkCtx firstMatch;

  expandTraits =
    traitList:
    let
      go =
        seen: queue:
        if queue == [ ] then
          seen
        else
          let
            t = builtins.head queue;
            rest = builtins.tail queue;
          in
          if builtins.any (s: s.name == t.name) seen then
            go seen rest
          else
            go (seen ++ [ t ]) (rest ++ (t.needs or [ ]));
    in
    go [ ] traitList;

  expandNeededBy =
    traits: nodeIs:
    let
      allTraitInstances = builtins.attrValues traits;
      go =
        nodeIsAcc:
        let
          nodeNames = map (t: t.name) nodeIsAcc;
          extras = builtins.filter (
            t:
            (t.neededBy or [ ]) != [ ]
            && !(builtins.elem t.name nodeNames)
            && builtins.any (nb: builtins.elem nb.name nodeNames) (t.neededBy or [ ])
          ) allTraitInstances;
        in
        if extras == [ ] then nodeIsAcc else go (expandTraits (nodeIsAcc ++ extras));
    in
    go nodeIs;

  deepMerge =
    a: b:
    if !builtins.isAttrs a || !builtins.isAttrs b then
      b
    else if b == { } then
      a
    else if a == { } then
      b
    else
      let
        aKeys = builtins.attrNames a;
        bKeys = builtins.attrNames b;
        commonKeys = builtins.filter (k: builtins.elem k aKeys) bKeys;
      in
      builtins.foldl' (
        acc: k:
        acc
        // {
          ${k} = if builtins.elem k commonKeys then deepMerge a.${k} b.${k} else b.${k};
        }
      ) a bKeys;

  applySynth =
    traits: refNodes: synthFns: parentNode:
    let
      ctx = mkCtx parentNode refNodes;
      synthResults = map (
        fn:
        if builtins.functionArgs fn == { } then
          fn ctx.select
        else
          selectorsLib.callWithArgs fn parentNode ctx
      ) synthFns;
      merged = builtins.foldl' deepMerge { } synthResults;
      nodeData = merged.node or { };
      plainAttrs = builtins.removeAttrs nodeData [ "children" ];
      rawChildren = nodeData.children or [ ];
      expandChild =
        child:
        let
          childIs = map (x: if builtins.isString x then traits.${x} else x) (child.is or [ ]);
          expandedIs = expandTraits childIs;
          fullIs = expandNeededBy traits expandedIs;
        in
        child
        // {
          __path = "${parentNode.__path}.${child.name}";
          __parentPath = parentNode.__path;
          is = fullIs;
        };
    in
    {
      node = parentNode // plainAttrs;
      children = map expandChild rawChildren;
    };
in
{
  inherit
    expandTraits
    expandNeededBy
    applySynth
    deepMerge
    ;
}
