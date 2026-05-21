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
  resolve =
    {
      local ? null,
      imported ? null,
      inherited ? null,
    }:
    if local != null then
      local
    else if imported != null then
      imported
    else
      inherited;

  # Generalized query combinator (van Antwerpen §2.1).
  # Subsumes inherit_, collectImports, and resolve as special cases.
  query =
    {
      dataFilter,
      labelWF ? "PI",
    }:
    self: id:
    let
      node = self.nodes.${id};
      local = dataFilter node;
      imported =
        if lib.hasInfix "I" labelWF then
          let
            results = lib.concatMap (
              importId:
              let
                v = dataFilter self.nodes.${importId};
              in
              lib.optional (v != null) v
            ) node.imports;
          in
          if results == [ ] then null
          # For attrset results, shadow-merge (Neron §5). For scalars, last wins.
          else if builtins.isAttrs (builtins.head results) then
            lib.foldl' (acc: v: shadow v acc) { } results
          else
            lib.last results
        else
          null;
      inherited =
        if lib.hasInfix "P" labelWF && node.parent != null then
          query { inherit dataFilter labelWF; } self node.parent
        else
          null;
    in
    resolve {
      inherit local imported inherited;
    };

  # Inherited: walks parent chain until resolved.
  # allowParent encodes well-formedness P*.I* (Neron §2.4).
  inherit_ =
    {
      resolve ? _: null,
      allowParent ? true,
    }:
    self: id:
    let
      node = self.nodes.${id};
      result = resolve node;
    in
    if result != null then
      result
    else if !allowParent then
      null
    else if node.parent == null then
      null
    else
      inherit_ { inherit resolve; } self node.parent;

  # Parameterized attribute (Sloane 2010 §3, JastAdd).
  paramAttr = f: self: id: param: f self id param;

  # Circular attribute: iterate from initial value until fixed-point (Sloane 2010 §2.2).
  circular =
    {
      init,
      eq ? a: b: a == b,
      maxIter ? 10,
    }:
    f: self: id:
    let
      go =
        n: prev:
        let
          next = f self id prev;
        in
        if n >= maxIter then
          throw "scope-engine: circular attribute on '${id}' did not converge after ${toString maxIter} iterations"
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
in
{
  inherit
    shadow
    resolve
    query
    inherit_
    paramAttr
    circular
    collectImports
    subtypeOf
    collect
    ;
}
