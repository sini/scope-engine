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
      traits = nestCfg.traits or { };
      rules =
        let
          r = nestCfg.rules or [ ];
        in
        if builtins.isList r then
          r
        else
          lib.mapAttrsToList (_: v: v) (builtins.removeAttrs r [ "_module" ]);
      domInput = builtins.removeAttrs nestCfg [
        "traits"
        "rules"
      ];

      # Resolve string refs in node.is to trait instances
      resolveIs =
        node:
        let
          resolved = map (x: if builtins.isString x then traits.${x} else x) node.is;
        in
        node // { is = resolved; };

      # Phase 1: DOM traversal + trait expansion
      rawNodes = walkDom domInput;
      resolvedNodes = map resolveIs rawNodes;
      expandedNodes = map (
        n:
        let
          expandedIs = expandTraits n.is;
          fullIs = expandNeededBy traits expandedIs;
        in
        n // { is = fullIs; }
      ) resolvedNodes;

      # Phase 2: Trait synth
      synthesizedNodes = synthesizeNodes traits expandedNodes;

      # Build gen-scope graph for structural queries
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
      finalAnnotated = applyRuleSynth traits rules annotated synthesizedNodes;

      # Phase 5: Output processing -- root nodes only
      rootNodes = builtins.filter (
        n: !builtins.any (m: m.__path == n.__parentPath) finalAnnotated
      ) finalAnnotated;
      rawOutputs = builtins.filter (x: x != null && x.value != null) (
        map (n: processNode n finalAnnotated) rootNodes
      );
      outputs = builtins.listToAttrs (
        map (x: {
          name = x.name;
          value = x.value;
        }) rawOutputs
      );
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

  # Process a root entity node. Collects child class contributions recursively,
  # merges with own rule-matched modules, then calls the class function.
  processNode =
    node: allAnnotated:
    let
      entityT = firstMatch (t: (t.class or { }) != { }) node.is;
    in
    if entityT == null then
      null
    else
      let
        classFns = entityT.class;
        allMods = mergeModuleLists (node.__mergedCfg or { }) (collectChildFrags node allAnnotated);
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

  # Recursively collect child class contributions.
  collectChildFrags =
    parentNode: allAnnotated:
    let
      children = builtins.filter (n: n.__parentPath == parentNode.__path) allAnnotated;
      childContrib =
        child:
        let
          entityT = firstMatch (t: (t.class or { }) != { }) child.is;
        in
        if entityT == null then
          { }
        else
          let
            classFns = entityT.class;
            childMods = mergeModuleLists (child.__mergedCfg or { }) (collectChildFrags child allAnnotated);
            ctx = mkCtx child allAnnotated;
          in
          builtins.foldl' (
            acc: className:
            if !(classFns ? ${className}) then
              acc
            else
              let
                result = (classFns.${className}) ctx.select (childMods.${className} or [ ]);
              in
              if result == null then
                acc
              else if builtins.isAttrs result then
                builtins.foldl' (
                  a: k:
                  let
                    v = result.${k};
                  in
                  a // { ${k} = (a.${k} or [ ]) ++ (if builtins.isList v then v else [ v ]); }
                ) acc (builtins.attrNames result)
              else
                acc
          ) { } (builtins.attrNames classFns);
    in
    builtins.foldl' mergeModuleLists { } (map childContrib children);

  mergeRuleConfigs =
    node: rules: ctx:
    builtins.foldl' (
      acc: rule:
      builtins.foldl' (
        a: key:
        let
          result = if builtins.isFunction rule.${key} then callWithArgs rule.${key} node ctx else rule.${key};
        in
        if key == "synth" then
          a // { synth = deepMerge (a.synth or { }) result; }
        else
          a // { ${key} = (a.${key} or [ ]) ++ [ result ]; }
      ) acc (builtins.attrNames (builtins.removeAttrs rule [ "is" ]))
    ) { } rules;

  # Trait synth: run synth fns from entity trait only (first trait with class).
  synthesizeNodes =
    traits: expandedNodes:
    let
      synthOne =
        node:
        let
          entityT = firstMatch (t: (t.class or { }) != { }) node.is;
          synthFns =
            if entityT != null && entityT ? synth then
              (if builtins.isList entityT.synth then entityT.synth else [ entityT.synth ])
            else
              [ ];
        in
        if synthFns == [ ] then
          {
            inherit node;
            children = [ ];
          }
        else
          applySynth traits expandedNodes synthFns node;
    in
    builtins.concatMap (
      node:
      let
        r = synthOne node;
      in
      [ r.node ] ++ r.children
    ) expandedNodes;

  applyRuleSynth =
    traits: rules: annotated: synthesizedNodes:
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
          applySynth traits synthesizedNodes [ (_: extra) ] node;
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
