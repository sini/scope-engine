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
in
{
  inherit
    parent
    children
    childrenIds
    ancestors
    siblings
    descendants
    ;
}
