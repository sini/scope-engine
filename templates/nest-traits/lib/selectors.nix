{ lib, engine }:
let
  css = import ./css.nix;

  firstMatch =
    pred: list:
    let
      ms = builtins.filter pred list;
    in
    if ms == [ ] then null else builtins.head ms;

  mkCtx =
    node: allNodes:
    let
      childOf = p: builtins.filter (n: n.__parentPath == p.__path) allNodes;
      children = childOf node;
      ancestors =
        let
          go =
            path:
            if path == null then
              [ ]
            else
              let
                p = firstMatch (n: n.__path == path) allNodes;
              in
              if p == null then [ ] else [ p ] ++ go p.__parentPath;
        in
        go node.__parentPath;
      siblings = builtins.filter (
        n: n.__parentPath == node.__parentPath && n.__path != node.__path
      ) allNodes;
      parentNode = if ancestors == [ ] then null else builtins.head ancestors;
      matchN = n: sel: matchesOne n sel (mkCtx n allNodes);
      mkFilter = list: sel: builtins.filter (n: matchN n sel) list;
      descendants =
        nd:
        let
          cs = childOf nd;
        in
        cs ++ builtins.concatLists (map descendants cs);
    in
    {
      inherit children ancestors allNodes;
      select = {
        __functor = _: mkFilter allNodes;
        node = node;
        parentNode = parentNode;
        within = nd: mkFilter (descendants nd);
        siblings = mkFilter siblings;
        children = mkFilter children;
        parent = mkFilter (if parentNode == null then [ ] else [ parentNode ]);
        parents = mkFilter ancestors;
      };
    };

  mkCtxFromGraph =
    nodeMap: node: allNodes:
    let
      findNode = id: firstMatch (n: n.__path == id) allNodes;
      cids = engine.childrenIds { nodes = nodeMap; } node.__path;
      children = map findNode cids;
      ancestorIds = engine.ancestors { nodes = nodeMap; } node.__path;
      ancestors = map findNode ancestorIds;
      siblingIds = engine.siblings { nodes = nodeMap; } node.__path;
      siblings = map findNode siblingIds;
      parentNode = if ancestors == [ ] then null else builtins.head ancestors;
      matchN = n: sel: matchesOne n sel (mkCtxFromGraph nodeMap n allNodes);
      mkFilter = list: sel: builtins.filter (n: matchN n sel) list;
      descendants =
        nd:
        let
          cs = builtins.filter (n: n.__parentPath == nd.__path) allNodes;
        in
        cs ++ builtins.concatLists (map descendants cs);
    in
    {
      inherit children ancestors allNodes;
      select = {
        __functor = _: mkFilter allNodes;
        node = node;
        parentNode = parentNode;
        within = nd: mkFilter (descendants nd);
        siblings = mkFilter siblings;
        children = mkFilter children;
        parent = mkFilter (if parentNode == null then [ ] else [ parentNode ]);
        parents = mkFilter ancestors;
      };
    };

  matchesOne =
    node: sel: ctx:
    if builtins.isList sel then
      builtins.all (s: matchesOne node s ctx) sel
    else if builtins.isString sel then
      matchesOne node (css.parseCssSel sel) ctx
    else if sel ? __sel then
      matchesSel node sel ctx
    else if sel ? __traitName then
      builtins.any (t: t ? __traitName && t.__traitName == sel.__traitName) node.is
    else
      false;

  matchesSel =
    node: sel: ctx:
    let
      handlers = {
        star = true;
        id = node.name == sel.name;
        name = node.name == sel.name;
        attr = (node ? ${sel.key}) && builtins.toString node.${sel.key} == sel.val;
        attrExists = node ? ${sel.key};
        attrs = builtins.all (k: (node ? ${k}) && node.${k} == sel.attrs.${k}) (
          builtins.attrNames sel.attrs
        );
        or = builtins.any (x: matchesOne node x ctx) sel.selectors;
        not =
          let
            notSels = if builtins.isList sel.selector then sel.selector else [ sel.selector ];
          in
          !(builtins.any (s: matchesOne node s ctx) notSels);
        has = builtins.any (n: matchesOne n sel.selector (mkCtx n ctx.allNodes)) ctx.children;
        within = builtins.any (n: matchesOne n sel.selector (mkCtx n ctx.allNodes)) ctx.ancestors;
        when = callWithArgs sel.fn node ctx;
        class =
          let
            entityT = firstMatch (x: x ? class) node.is;
          in
          entityT != null && entityT.class ? ${sel.name};
        child =
          let
            parentNode' = firstMatch (_: true) ctx.ancestors;
          in
          parentNode' != null
          && matchesOne node sel.childSel ctx
          && matchesOne parentNode' sel.parentSel (mkCtx parentNode' ctx.allNodes);
        descendant =
          matchesOne node sel.descendantSel ctx
          && builtins.any (a: matchesOne a sel.ancestorSel (mkCtx a ctx.allNodes)) ctx.ancestors;
      };
    in
    handlers.${sel.__sel} or false;

  callWithArgs =
    fn: node: ctx:
    let
      entityT = firstMatch (t: t ? class) (node.is or [ ]);
      entityArgs = if entityT != null then { ${entityT.__traitName} = node; } else { };
    in
    fn (builtins.intersectAttrs (builtins.functionArgs fn) ({ select = ctx.select; } // entityArgs));

  constructors = {
    star = {
      __sel = "star";
    };
    attrs = a: {
      __sel = "attrs";
      attrs = a;
    };
    or = ss: {
      __sel = "or";
      selectors = ss;
    };
    not = s: {
      __sel = "not";
      selector = s;
    };
    has = s: {
      __sel = "has";
      selector = s;
    };
    within = s: {
      __sel = "within";
      selector = s;
    };
    when = f: {
      __sel = "when";
      fn = f;
    };
    class = n: {
      __sel = "class";
      name = n;
    };
    child = p: c: {
      __sel = "child";
      parentSel = p;
      childSel = c;
    };
    descendant = a: d: {
      __sel = "descendant";
      ancestorSel = a;
      descendantSel = d;
    };
  };
in
{
  inherit
    matchesOne
    matchesSel
    callWithArgs
    mkCtx
    mkCtxFromGraph
    firstMatch
    constructors
    ;
}
