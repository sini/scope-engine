{
  lib,
  engine,
  selectorsLib,
}:
let
  inherit (selectorsLib) matchesOne mkCtx firstMatch;

  traitSpecialKeys = [
    "class"
    "needs"
    "neededBy"
    "synth"
    "__traitName"
  ];

  flattenTraitTree =
    tree:
    builtins.concatLists (
      map (
        k:
        let
          v = tree.${k};
        in
        if builtins.isAttrs v && v ? __traitName then
          [ v ] ++ flattenTraitTree (builtins.removeAttrs v traitSpecialKeys)
        else
          [ ]
      ) (builtins.attrNames tree)
    );

  expandTraits =
    processedTraits: traitList: allNodes:
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
          if builtins.any (s: s.__traitName == t.__traitName) seen then
            go seen rest
          else
            let
              rawNeeds = t.needs or null;
              needed =
                if rawNeeds == null then
                  [ ]
                else if builtins.isFunction rawNeeds then
                  rawNeeds processedTraits
                else
                  rawNeeds;
            in
            go (seen ++ [ t ]) (rest ++ needed);
    in
    go [ ] traitList;

  expandNeededBy =
    processedTraits: nodeIs: nodeAttrs: allNodes:
    let
      allTraits = flattenTraitTree processedTraits;
      go =
        nodeIsAcc:
        let
          virtualNode = nodeAttrs // {
            is = nodeIsAcc;
          };
          ctx = mkCtx virtualNode allNodes;
          extras = builtins.filter (
            t:
            (t ? neededBy)
            && t.neededBy != [ ]
            && !(builtins.any (s: s.__traitName == t.__traitName) nodeIsAcc)
            && builtins.any (sel: matchesOne virtualNode sel ctx) t.neededBy
          ) allTraits;
        in
        if extras == [ ] then
          nodeIsAcc
        else
          go (expandTraits processedTraits (nodeIsAcc ++ extras) allNodes);
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
    processedTraits: refNodes: synthFns: parentNode:
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
          expandedIs = expandTraits processedTraits child.is refNodes;
          fullIs = expandNeededBy processedTraits expandedIs (builtins.removeAttrs child [ "is" ]) refNodes;
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
    flattenTraitTree
    deepMerge
    traitSpecialKeys
    ;
}
