{
  lib,
  engine,
  selectorsLib,
}:
let
  inherit (selectorsLib) matchesOne mkCtx firstMatch;
  css = import ./css.nix;

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
            let
              needed = map (
                n:
                if builtins.isString n then throw "nest: unresolved trait ref '${n}' in needs of '${t.name}'" else n
              ) (t.needs or [ ]);
            in
            go (seen ++ [ t ]) (rest ++ needed);
    in
    go [ ] traitList;

  matchesNeededByEntry =
    traits: entry: node: ctx:
    if entry ? name && entry ? needs then
      builtins.any (t: t.name == entry.name) node.is
    else if builtins.isString entry then
      if traits ? ${entry} then
        builtins.any (t: t.name == entry) node.is
      else
        matchesOne node (css.parseCssSel entry) ctx
    else
      matchesOne node entry ctx;

  expandNeededBy =
    traits: nodeIs: nodeAttrs: allNodes:
    let
      allTraitNames = builtins.attrNames traits;
      go =
        nodeIsAcc:
        let
          virtualNode = nodeAttrs // {
            is = nodeIsAcc;
          };
          ctx = mkCtx virtualNode allNodes;
          extras = builtins.filter (
            name:
            let
              t = traits.${name};
              nb = t.neededBy or [ ];
            in
            nb != [ ]
            && !(builtins.any (s: s.name == name) nodeIsAcc)
            && builtins.any (entry: matchesNeededByEntry traits entry virtualNode ctx) nb
          ) allTraitNames;
          extraInstances = map (name: traits.${name}) extras;
        in
        if extras == [ ] then nodeIsAcc else go (expandTraits (nodeIsAcc ++ extraInstances));
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
          fullIs = expandNeededBy traits expandedIs (builtins.removeAttrs child [ "is" ]) refNodes;
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
    matchesNeededByEntry
    ;
}
