# Resolution primitives and named attribute constructors.
#
# Neron (2015) and van Antwerpen (2018) resolution semantics.
# Kiama-inspired vocabulary (Sloane et al., 2010) for attribute definitions.
{ lib }:
let
  # Shadow: merge two declaration sets, inner shadows outer (Neron §5 Def. 1).
  shadow =
    inner: outer:
    inner // lib.filterAttrs (k: _: !(inner ? ${k})) outer;

  # Resolve with specificity ordering D < I < P (Neron Fig. 2).
  # Default: local shadows import, import shadows parent.
  # Override via specificity parameter for alternative policies (Neron §2.5, van Antwerpen §2.1).
  resolve =
    {
      local ? null,
      imported ? null,
      inherited ? null,
      localShadowsImport ? true,
      importShadowsParent ? true,
    }:
    if local != null && localShadowsImport then
      local
    else if imported != null && importShadowsParent then
      imported
    else if local != null then
      # local doesn't shadow import but no import found
      local
    else if imported != null then
      # import doesn't shadow parent but no parent found
      imported
    else
      inherited;

  # Generalized query combinator (van Antwerpen §2.1).
  # Subsumes inherit', collectImports, and resolve as special cases.
  # _seen tracks visited scopes to prevent import self-resolution (Neron 2015 §2.4, rule X).
  query =
    {
      dataFilter,
      labelWF ? "PI",
      # Specificity policy (Neron §2.5, van Antwerpen §2.1).
      localShadowsImport ? true,
      importShadowsParent ? true,
      # Transitive imports: follow imported scopes' own imports (Neron §2.5, P*.I*).
      # When false (default), only direct imports are checked (P*.I?).
      transitiveImports ? false,
      _seen ? { },
    }:
    self: id:
    let
      node = self.nodes.${id};
      local = dataFilter node;
      # Collect results from a single imported scope, optionally following its imports.
      collectFromImport = seen: importId:
        let
          v = dataFilter self.nodes.${importId};
          direct = lib.optional (v != null) v;
          transitive =
            if transitiveImports then
              let
                importNode = self.nodes.${importId};
                nextUnseen = builtins.filter (iid: !(seen ? ${iid})) importNode.imports;
                nextSeen = seen // { ${importId} = true; };
              in
              lib.concatMap (collectFromImport nextSeen) nextUnseen
            else
              [ ];
        in
        direct ++ transitive;
      imported =
        if lib.hasInfix "I" labelWF then
          let
            # Filter out already-seen imports to prevent cycles (Neron §2.4).
            unseenImports = builtins.filter (iid: !(_seen ? ${iid})) node.imports;
            results = lib.concatMap (collectFromImport (_seen // { ${id} = true; })) unseenImports;
          in
          if results == [ ] then null
          # For attrset results, shadow-merge (Neron §5). For scalars, first wins
          # (more direct imports shadow transitive ones).
          else if builtins.isAttrs (builtins.head results) then
            lib.foldl' (acc: v: shadow v acc) { } results
          else
            builtins.head results
        else
          null;
      inherited =
        if lib.hasInfix "P" labelWF && node.parent != null then
          query {
            inherit dataFilter labelWF localShadowsImport importShadowsParent transitiveImports;
            _seen = _seen // (builtins.listToAttrs (map (id: { name = id; value = true; }) node.imports));
          } self node.parent
        else
          null;
    in
    resolve {
      inherit local imported inherited localShadowsImport importShadowsParent;
    };

  # Inherited: walks parent chain until resolved.
  # allowParent encodes well-formedness P*.I* (Neron §2.4).
  # _visited prevents infinite loops on malformed parent cycles.
  inherit' =
    {
      resolve ? _: null,
      allowParent ? true,
      _visited ? { },
    }:
    self: id:
    let
      node = self.nodes.${id};
      result = resolve node;
    in
    if _visited ? ${id} then
      throw "gen-scope: parent cycle detected at '${id}' (parent relation must be well-founded, Neron §2.2)"
    else if result != null then
      result
    else if !allowParent then
      null
    else if node.parent == null then
      null
    else
      inherit' { inherit resolve; _visited = _visited // { ${id} = true; }; } self node.parent;

  # Inherited accumulator: walks parent chain collecting ALL values (Neron 2015 §2.4).
  # Unlike inherit' which returns the first match, inheritAll combines all ancestors.
  inheritAll =
    {
      extract,
      combine ? a: b: a ++ b,
      _visited ? { },
    }:
    self: id:
    let
      node = self.nodes.${id};
      local = extract node;
      localResults = if local != null then (if builtins.isList local then local else [ local ]) else [ ];
    in
    if _visited ? ${id} then
      localResults
    else if node.parent == null then
      localResults
    else
      let
        parentResults = inheritAll {
          inherit extract combine;
          _visited = _visited // { ${id} = true; };
        } self node.parent;
      in
      combine localResults parentResults;

  # Parameterized attribute (Sloane 2010 §3, JastAdd).
  paramAttr = f: self: id: param: f self id param;

  # Circular attribute: iterate from initial value until fixed-point (Sloane 2010 §2.2).
  circular =
    {
      init,
      eq ? a: b: a == b,
      maxIter ? 100,
    }:
    f: self: id:
    let
      go =
        n: prev:
        let
          next = f self id prev;
        in
        if n >= maxIter then
          throw "gen-scope: circular attribute on '${id}' did not converge after ${toString maxIter} iterations"
        else if eq prev next then
          next
        else
          go (n + 1) next;
    in
    go 0 init;

  # Import-scoped collection: demand-driven, only imported scopes (Neron §2.4, rule I).
  collectImports =
    extract: self: id:
    lib.concatMap (importId: extract self importId) self.nodes.${id}.imports;

  # Structural subtyping: check if A's decls are a subset of B's (van Antwerpen §2.3).
  subtypeOf =
    {
      eq ? _k: _a: _b: true,
    }:
    self: idA: idB:
    let
      declsA = self.nodes.${idA}.decls;
      declsB = self.nodes.${idB}.decls;
    in
    builtins.all (
      k: declsB ? ${k} && eq k declsA.${k} declsB.${k}
    ) (builtins.attrNames declsA);

  # Convenience: resolve single visible declaration from a scope (Neron §2.3).
  # Thin wrapper over query — returns the single visible value or null.
  visibleFrom = dataFilter: self: nodeId:
    query { inherit dataFilter; } self nodeId;

  # Collection attribute combinator (Sloane 2010, §7 — Kiama collection attributes).
  # Traverses scope neighbors matching a predicate, extracts values, combines results.
  collectionAttr =
    {
      traverse ? "imports",
      extract,
      combine ? a: b: a ++ b,
      filter ? _: true,
    }:
    self: id:
    let
      targets =
        if builtins.isFunction traverse then
          traverse self id
        else if traverse == "imports" then
          self.nodes.${id}.imports
        else if traverse == "children" then
          self.nodes.${id}.childrenIds
        else if traverse == "siblings" then
          let
            p = self.nodes.${id}.parent;
          in
          if p == null then [ ] else builtins.filter (cid: cid != id) self.nodes.${p}.childrenIds
        else if traverse == "ancestors" then
          let
            go =
              visited: nid:
              if nid == null || visited ? ${nid} then [ ] else [ nid ] ++ go (visited // { ${nid} = true; }) self.nodes.${nid}.parent;
          in
          go { ${id} = true; } self.nodes.${id}.parent
        else if lib.hasPrefix "label:" traverse then
          self.nodes.${id}.edgesByLabel.${lib.removePrefix "label:" traverse} or [ ]
        else
          throw "gen-scope: collectionAttr: unknown traverse mode '${traverse}'";
      filtered = builtins.filter (tid: filter self.nodes.${tid}) targets;
      perTarget = map (
        tid:
        let
          r = extract self tid;
        in
        if r == null then [ ] else if builtins.isList r then r else [ r ]
      ) filtered;
    in
    builtins.foldl' combine [ ] perTarget;

  # Global collection (WARNING: iterates all nodes — prefer collectImports).
  collect =
    {
      filter ? _: true,
    }:
    extract: self:
    lib.concatMap (
      id:
      let
        node = self.nodes.${id};
      in
      if filter node then extract self id else [ ]
    ) (builtins.attrNames self.nodes);

  # Typed collection: filter nodes by type field.
  # WARNING: iterates all nodes (delegates to collect). Prefer collectImports for demand-driven queries.
  collectByType =
    type: extract: self:
    collect { filter = n: n.type == type; } extract self;

  # Follow a custom edge label from a node (van Antwerpen 2018 §2.1).
  # Returns list of target node IDs for the given label.
  followEdge = label: self: id:
    self.nodes.${id}.edgesByLabel.${label} or [ ];

  # Collect data from nodes reachable via a custom edge label.
  collectByLabel =
    label: extract: self: id:
    lib.concatMap (targetId: extract self targetId) (followEdge label self id);

  # Ambiguity detection (van Antwerpen 2018 §2.3).
  # Returns true when multiple declarations are reachable and none shadows the other.
  # Uses queryAll to find all reachable results and checks for duplicates.
  ambiguous =
    args: self: id:
    let
      all = queryAll args self id;
    in
    builtins.length all > 1;

  # Return all reachable results (list) without shadowing (Neron 2015 §2.3, rule R).
  # Unlike query which returns the single visible result, queryAll returns every
  # reachable declaration for ambiguity detection.
  queryAll =
    {
      dataFilter,
      labelWF ? "PI",
      transitiveImports ? false,
      _seen ? { },
    }:
    self: id:
    let
      node = self.nodes.${id};
      local = dataFilter node;
      unseenImports = builtins.filter (iid: !(_seen ? ${iid})) node.imports;
      collectFromImportAll = seen: importId:
        let
          v = dataFilter self.nodes.${importId};
          direct = lib.optional (v != null) v;
          transitive =
            if transitiveImports then
              let
                importNode = self.nodes.${importId};
                nextUnseen = builtins.filter (iid: !(seen ? ${iid})) importNode.imports;
                nextSeen = seen // { ${importId} = true; };
              in
              lib.concatMap (collectFromImportAll nextSeen) nextUnseen
            else
              [ ];
        in
        direct ++ transitive;
      importResults =
        if lib.hasInfix "I" labelWF then
          lib.concatMap (collectFromImportAll (_seen // { ${id} = true; })) unseenImports
        else
          [ ];
      parentResults =
        if lib.hasInfix "P" labelWF && node.parent != null then
          queryAll {
            inherit dataFilter labelWF transitiveImports;
            _seen = _seen // (builtins.listToAttrs (map (id: { name = id; value = true; }) node.imports));
          } self node.parent
        else
          [ ];
    in
    (lib.optional (local != null) local) ++ importResults ++ parentResults;
in
{
  inherit
    shadow
    resolve
    query
    queryAll
    ambiguous
    visibleFrom
    collectionAttr
    inherit'
    inheritAll
    paramAttr
    circular
    collectImports
    subtypeOf
    collect
    collectByType
    followEdge
    collectByLabel
    ;
}
