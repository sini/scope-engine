{
  lib,
  engine,
  selectorsLib,
  traitsLib,
  dom,
}:
let
  inherit (selectorsLib)
    matchesOne
    mkCtx
    mkCtxFromGraph
    callWithArgs
    firstMatch
    ;
  inherit (traitsLib)
    expandTraits
    expandNeededBy
    applySynth
    deepMerge
    ;
  inherit (dom) walkDom;

  evalNest =
    nestCfg:
    let
      processedTraits = nestCfg.trait or { };
      rules =
        let
          r = nestCfg.rules or [ ];
        in
        if builtins.isList r then
          r
        else
          lib.mapAttrsToList (_: v: v) (builtins.removeAttrs r [ "_module" ]);
      domInput = builtins.removeAttrs nestCfg [
        "trait"
        "rules"
      ];

      # Phase 1: DOM traversal + trait expansion
      rawNodes = walkDom processedTraits domInput;
      expandedNodes = map (
        n:
        let
          expandedIs = expandTraits processedTraits n.is rawNodes;
          fullIs = expandNeededBy processedTraits expandedIs (builtins.removeAttrs n [ "is" ]) rawNodes;
        in
        n // { is = fullIs; }
      ) rawNodes;

      # Phase 2: Trait synth
      synthesizedNodes = synthesizeNodes processedTraits expandedNodes;

      # Build scope-engine graph for structural queries
      synthGraph = dom.buildDomGraph synthesizedNodes;

      # Phase 3: Rule annotation
      annotated = map (
        node:
        let
          ctx = mkCtxFromGraph synthGraph node synthesizedNodes;
          matchingRules = builtins.filter (r: matchesOne node r.is ctx) rules;
        in
        node // { __mergedCfg = mergeRuleConfigs node matchingRules ctx; }
      ) synthesizedNodes;

      # Phase 4: Rule synth
      finalAnnotated = applyRuleSynth processedTraits rules annotated synthesizedNodes;

      # Phase 5: Output processing
      rawOutputs = builtins.filter (x: x != null && x.value != null) (
        map (n: processNode n finalAnnotated) finalAnnotated
      );
      outputs = builtins.listToAttrs (map (x: {
        name = x.name;
        value = x.value;
      }) rawOutputs);
      byClass = builtins.foldl' (
        acc: x:
        acc
        // {
          ${x.className} = (acc.${x.className} or { }) // {
            ${x.name} = x.value;
          };
        }
      ) { } rawOutputs;
    in
    {
      inherit outputs byClass;
      _nodes = finalAnnotated;
    };

  # Process a single node: find its entity trait (one with class), call the class
  # function with collected modules from rules
  processNode =
    node: allAnnotated:
    let
      entityT = firstMatch (t: t ? class) node.is;
    in
    if entityT == null then
      null
    else
      let
        classFns = entityT.class;
        allMods = node.__mergedCfg or { };
        ctx = mkCtx node allAnnotated;
      in
      firstMatch (result: result != null) (
        map (
          className:
          let
            value = (classFns.${className}) ctx.select (allMods.${className} or [ ]);
          in
          if value != null then
            {
              name = node.name;
              inherit className value;
            }
          else
            null
        ) (builtins.attrNames classFns)
      );

  mergeRuleConfigs =
    node: rules: ctx:
    builtins.foldl' (
      acc: rule:
      builtins.foldl' (
        a: key:
        let
          result =
            if builtins.isFunction rule.${key} then callWithArgs rule.${key} node ctx else rule.${key};
        in
        if key == "synth" then
          a // { synth = deepMerge (a.synth or { }) result; }
        else
          a // { ${key} = (a.${key} or [ ]) ++ [ result ]; }
      ) acc (builtins.attrNames (builtins.removeAttrs rule [ "is" ]))
    ) { } rules;

  synthesizeNodes =
    processedTraits: expandedNodes:
    let
      synthOne =
        node:
        let
          synthFns = builtins.concatMap (
            t:
            if t ? synth then (if builtins.isList t.synth then t.synth else [ t.synth ]) else [ ]
          ) node.is;
        in
        if synthFns == [ ] then
          {
            inherit node;
            children = [ ];
          }
        else
          applySynth processedTraits expandedNodes synthFns node;
    in
    builtins.concatMap (
      node:
      let
        r = synthOne node;
      in
      [ r.node ] ++ r.children
    ) expandedNodes;

  applyRuleSynth =
    processedTraits: rules: annotated: synthesizedNodes:
    let
      synthOne =
        node:
        let
          extra = node.__mergedCfg.synth or null;
        in
        if extra == null then
          {
            inherit node;
            children = [ ];
          }
        else
          applySynth processedTraits synthesizedNodes [ (_: extra) ] node;
      withSynth = builtins.concatMap (
        node:
        let
          r = synthOne node;
        in
        [ r.node ] ++ r.children
      ) annotated;
      origPaths = builtins.listToAttrs (
        map (n: {
          name = n.__path;
          value = true;
        }) annotated
      );
      newChildren = builtins.filter (n: !(origPaths ? ${n.__path})) withSynth;
      annotatedChildren = map (
        child:
        let
          ctx = mkCtx child withSynth;
          matchingRules = builtins.filter (r: matchesOne child r.is ctx) rules;
        in
        child // { __mergedCfg = mergeRuleConfigs child matchingRules ctx; }
      ) newChildren;
    in
    builtins.filter (n: origPaths ? ${n.__path}) withSynth ++ annotatedChildren;

  mergeModuleLists =
    a: b:
    let
      aKeys = builtins.attrNames a;
      bKeys = builtins.attrNames b;
      allKeys = aKeys ++ builtins.filter (k: !(builtins.elem k aKeys)) bKeys;
    in
    builtins.listToAttrs (
      map (k: {
        name = k;
        value = (a.${k} or [ ]) ++ (b.${k} or [ ]);
      }) allKeys
    );
in
{
  inherit evalNest;
}
