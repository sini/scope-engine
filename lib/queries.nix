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
      p = self.nodes.${id}.parent;
    in
    if p == null then [ ] else [ p ] ++ ancestors self p;

  siblings =
    self: id:
    let
      p = self.nodes.${id}.parent;
    in
    if p == null then [ ] else builtins.filter (cid: cid != id) self.nodes.${p}.childrenIds;

  descendants =
    self: id:
    let
      direct = self.nodes.${id}.childrenIds;
    in
    direct ++ lib.concatMap (cid: descendants self cid) direct;

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
