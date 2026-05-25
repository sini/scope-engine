# Structural queries as thin wrappers over self.node and self.get.
#
# parent is structural (on the node). children, ancestors, descendants,
# siblings are derived via computed attributes (self.get id "children").
{ lib }:
let
  parent = self: id: (self.node id).parent;

  children = self: id: self.get id "children";

  childrenIds = self: id: builtins.attrNames (self.get id "children");

  ancestors = self: id:
    let
      go = visited: nid:
        let p = (self.node nid).parent;
        in if p == null then []
        else if visited ? ${p} then []
        else [ p ] ++ go (visited // { ${p} = true; }) p;
    in go { ${id} = true; } id;

  siblings = self: id:
    let p = (self.node id).parent;
    in if p == null then []
    else builtins.filter (cid: cid != id) (builtins.attrNames (self.get p "children"));

  descendants = self: id:
    let
      go = visited: nid:
        let cids = builtins.attrNames (self.get nid "children");
        in lib.concatMap (cid:
          if visited ? ${cid} then []
          else [ cid ] ++ go (visited // { ${cid} = true; }) cid
        ) cids;
    in go { ${id} = true; } id;

  isAncestor = self: ancestorId: id: builtins.elem ancestorId (ancestors self id);

  isDescendant = self: descendantId: id: builtins.elem descendantId (descendants self id);

  nodesByType = self: type:
    lib.filterAttrs (_: n: n.type == type) self.allNodes;
in
{
  inherit parent children childrenIds ancestors siblings descendants
    isAncestor isDescendant nodesByType;
}
