# Structural queries on the flat node map.
# These never trigger attribute evaluation — safe to call during HOAG synthesis.
{ lib }:
let
  parent = self: id: self.nodes.${id}.parent;

  children = self: id: lib.genAttrs self.nodes.${id}.childrenIds (cid: self.nodes.${cid});

  childrenIds = self: id: self.nodes.${id}.childrenIds;

  ancestors =
    self: id:
    let
      go =
        visited: nid:
        let
          p = self.nodes.${nid}.parent;
        in
        if p == null then
          [ ]
        else if visited ? ${p} then
          throw "gen-scope: ancestors: cycle detected at '${p}'"
        else
          [ p ] ++ go (visited // { ${p} = true; }) p;
    in
    go { ${id} = true; } id;

  siblings =
    self: id:
    let
      p = self.nodes.${id}.parent;
    in
    if p == null then [ ] else builtins.filter (cid: cid != id) self.nodes.${p}.childrenIds;

  descendants =
    self: id:
    let
      go =
        visited: nid:
        let
          direct = self.nodes.${nid}.childrenIds;
        in
        lib.concatMap (
          cid:
          if visited ? ${cid} then
            throw "gen-scope: descendants: cycle detected at '${cid}'"
          else
            [ cid ] ++ go (visited // { ${cid} = true; }) cid
        ) direct;
    in
    go { ${id} = true; } id;

  isAncestor = self: ancestorId: id: builtins.elem ancestorId (ancestors self id);

  isDescendant = self: descendantId: id: builtins.elem descendantId (descendants self id);

  # Return all nodes of a given type as an attrset.
  nodesByType = self: type:
    lib.filterAttrs (_: n: n.type == type) self.nodes;
in
{
  inherit
    parent
    children
    childrenIds
    ancestors
    siblings
    descendants
    isAncestor
    isDescendant
    nodesByType
    ;
}
