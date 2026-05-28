# Resolution primitives and named attribute constructors.
#
# Neron (2015) and van Antwerpen (2018) resolution semantics.
# Kiama-inspired vocabulary (Sloane et al., 2010) for attribute definitions.
#
# Key design: import edges are COMPUTED ATTRIBUTES (self.get id "imports"),
# not structural fields. This allows dynamic import resolution.
{ lib }:
let
  # Shadow: merge two declaration sets, inner shadows outer (Neron §5 Def. 1).
  shadow = inner: outer: inner // lib.filterAttrs (k: _: !(inner ? ${k})) outer;

  # Resolve with specificity ordering D < I < P (Neron Fig. 2).
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
      local
    else if imported != null then
      imported
    else
      inherited;

  # Generalized query combinator (van Antwerpen §2.1).
  # Import edges come from self.get id "imports" (computed attribute).
  # _seen tracks visited scopes to prevent import self-resolution (Neron §2.4, rule X).
  query =
    {
      dataFilter,
      localShadowsImport ? true,
      importShadowsParent ? true,
      transitiveImports ? false,
      _seen ? { },
    }:
    self: id:
    let
      node = self.node id;
      local = dataFilter node;
      importIds = self.get id "imports";
      unseenImports = builtins.filter (iid: !(_seen ? ${iid})) importIds;
      collectFromImport =
        seen: importId:
        let
          v = dataFilter (self.node importId);
          direct = lib.optional (v != null) v;
          transitive =
            if transitiveImports then
              let
                nextImports = self.get importId "imports";
                nextUnseen = builtins.filter (iid: !(seen ? ${iid})) nextImports;
                nextSeen = seen // {
                  ${importId} = true;
                };
              in
              lib.concatMap (collectFromImport nextSeen) nextUnseen
            else
              [ ];
        in
        direct ++ transitive;
      imported =
        let
          results = lib.concatMap (collectFromImport (_seen // { ${id} = true; })) unseenImports;
        in
        if results == [ ] then
          null
        else if builtins.isAttrs (builtins.head results) then
          lib.foldl' (acc: v: shadow v acc) { } results
        else
          builtins.head results;
      inherited =
        if node.parent != null then
          query {
            inherit
              dataFilter
              localShadowsImport
              importShadowsParent
              transitiveImports
              ;
            _seen =
              _seen
              // builtins.listToAttrs (
                map (iid: {
                  name = iid;
                  value = true;
                }) importIds
              );
          } self node.parent
        else
          null;
    in
    resolve {
      inherit
        local
        imported
        inherited
        localShadowsImport
        importShadowsParent
        ;
    };

  # Return all reachable results without shadowing (Neron §2.3, rule R).
  queryAll =
    {
      dataFilter,
      transitiveImports ? false,
      _seen ? { },
    }:
    self: id:
    let
      node = self.node id;
      local = dataFilter node;
      importIds = self.get id "imports";
      unseenImports = builtins.filter (iid: !(_seen ? ${iid})) importIds;
      collectFromImportAll =
        seen: importId:
        let
          v = dataFilter (self.node importId);
          direct = lib.optional (v != null) v;
          transitive =
            if transitiveImports then
              let
                nextImports = self.get importId "imports";
                nextUnseen = builtins.filter (iid: !(seen ? ${iid})) nextImports;
                nextSeen = seen // {
                  ${importId} = true;
                };
              in
              lib.concatMap (collectFromImportAll nextSeen) nextUnseen
            else
              [ ];
        in
        direct ++ transitive;
      importResults = lib.concatMap (collectFromImportAll (_seen // { ${id} = true; })) unseenImports;
      parentResults =
        if node.parent != null then
          queryAll {
            inherit dataFilter transitiveImports;
            _seen =
              _seen
              // builtins.listToAttrs (
                map (iid: {
                  name = iid;
                  value = true;
                }) importIds
              );
          } self node.parent
        else
          [ ];
    in
    (lib.optional (local != null) local) ++ importResults ++ parentResults;

  # Ambiguity detection (van Antwerpen §2.3).
  ambiguous =
    args: self: id:
    builtins.length (queryAll args self id) > 1;

  # Convenience: resolve single visible declaration from a scope.
  visibleFrom =
    dataFilter: self: nodeId:
    query { inherit dataFilter; } self nodeId;

  # Inherited attribute: walks parent chain until resolve returns non-null.
  # _visited prevents cycles on malformed parent relations.
  inherit' =
    {
      resolve,
      _visited ? { },
    }:
    self: id:
    let
      node = self.node id;
      result = resolve node;
    in
    if _visited ? ${id} then
      throw "gen-scope: parent cycle detected at '${id}'"
    else if result != null then
      result
    else if node.parent == null then
      null
    else
      inherit' {
        inherit resolve;
        _visited = _visited // {
          ${id} = true;
        };
      } self node.parent;

  # Inherited accumulator: walks parent chain collecting ALL values.
  inheritAll =
    {
      extract,
      combine ? a: b: a ++ b,
      _visited ? { },
    }:
    self: id:
    let
      node = self.node id;
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
          _visited = _visited // {
            ${id} = true;
          };
        } self node.parent;
      in
      combine localResults parentResults;

  # Parameterized attribute (Sloane 2010 §3, JastAdd).
  paramAttr =
    f: self: id: param:
    f self id param;

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

  # Collection attribute combinator (Sloane 2010 §7).
  # Traversal uses COMPUTED attributes (self.get), not structural fields.
  collectionAttr =
    {
      traverse,
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
          self.get id "imports"
        else if traverse == "children" then
          builtins.attrNames (self.get id "children")
        else if traverse == "siblings" then
          let
            p = (self.node id).parent;
          in
          if p == null then
            [ ]
          else
            builtins.filter (cid: cid != id) (builtins.attrNames (self.get p "children"))
        else if traverse == "ancestors" then
          let
            go =
              visited: nid:
              if nid == null || visited ? ${nid} then
                [ ]
              else
                [ nid ] ++ go (visited // { ${nid} = true; }) (self.node nid).parent;
          in
          go { ${id} = true; } (self.node id).parent
        else if traverse == "neron" then
          let
            neronCollect =
              seen: nid:
              let
                node = self.node nid;
                selfSeen = seen // {
                  ${nid} = true;
                };
                importIds = self.get nid "imports";
                unseenImports = builtins.filter (iid: !(selfSeen ? ${iid})) importIds;
                newSeen =
                  selfSeen
                  // builtins.listToAttrs (
                    map (iid: {
                      name = iid;
                      value = true;
                    }) importIds
                  );
                parentContribs =
                  if node.parent != null && !(newSeen ? ${node.parent}) then
                    neronCollect newSeen node.parent
                  else
                    [ ];
              in
              [ nid ] ++ unseenImports ++ parentContribs;
          in
          neronCollect { } id
        else if lib.hasPrefix "label:" traverse then
          self.get id "edges-${lib.removePrefix "label:" traverse}"
        else
          throw "gen-scope: collectionAttr: unknown traverse '${traverse}'";
      filtered = builtins.filter (tid: filter (self.node tid)) targets;
      perTarget = map (
        tid:
        let
          r = extract self tid;
        in
        if r == null then
          [ ]
        else if builtins.isList r then
          r
        else
          [ r ]
      ) filtered;
    in
    builtins.foldl' combine [ ] perTarget;

  # Import-scoped collection: demand-driven (Neron §2.4, rule I).
  collectImports =
    extract: self: id:
    lib.concatMap (importId: extract self importId) (self.get id "imports");

  # Global collection (WARNING: forces full tree via allNodes — Tier 2).
  collect =
    {
      filter ? _: true,
    }:
    extract: self:
    lib.concatMap (
      id:
      let
        node = self.node id;
      in
      if filter node then extract self id else [ ]
    ) (builtins.attrNames self.allNodes);

  # Typed collection: filter nodes by type field.
  collectByType =
    type: extract: self:
    collect { filter = n: n.type == type; } extract self;

  # Follow a custom edge label from a node.
  followEdge =
    label: self: id:
    self.get id "edges-${label}";

  # Collect data from nodes reachable via a custom edge label.
  collectByLabel =
    label: extract: self: id:
    lib.concatMap (targetId: extract self targetId) (followEdge label self id);

  # Structural subtyping (van Antwerpen §2.3).
  subtypeOf =
    {
      eq ?
        _k: _a: _b:
        true,
    }:
    self: idA: idB:
    let
      declsA = (self.node idA).decls;
      declsB = (self.node idB).decls;
    in
    builtins.all (k: declsB ? ${k} && eq k declsA.${k} declsB.${k}) (builtins.attrNames declsA);
in
{
  inherit
    shadow
    resolve
    query
    queryAll
    ambiguous
    visibleFrom
    inherit'
    inheritAll
    paramAttr
    circular
    collectionAttr
    collectImports
    collect
    collectByType
    followEdge
    collectByLabel
    subtypeOf
    ;
}
