# HOAG evaluator: demand-driven with co-located _eval memoization.
#
# Nix's native lazy evaluation provides scheduling, memoization, and cycle
# detection (Mokhov et al., 2018). Every attribute evaluates exactly once per
# node — including on dynamically synthesized nodes (Vogt et al., 1989).
#
# The key insight: Nix attrset VALUES are lazy but KEYS are eager. The only way
# to get O(1) attribute access is an attrset entry. We co-locate the memoization
# cache (_eval) ON each node when it is materialized by its parent's `children`
# or `derived-children` attribute.
{ lib }:
let
  eval =
    {
      roots,
      attributes,
      parseParent ? null,
    }:
    lib.fix (self: let
      # Wrap a child node with a lazy attribute cache (_eval).
      # The cache propagates recursively: _eval.children wraps grandchildren.
      wrapChild = childNode:
        childNode // {
          _eval = builtins.mapAttrs (attrName: fn:
            if attrName == "children" || attrName == "derived-children"
            then let raw = fn self childNode.id;
              in builtins.mapAttrs (_: wrapChild) raw
            else fn self childNode.id
          ) attributes;
        };

      # Root memoization: each root gets a lazy attrset of its attribute computations.
      rootEval = lib.mapAttrs (id: _:
        builtins.mapAttrs (attrName: fn:
          if attrName == "children" || attrName == "derived-children"
          then let raw = fn self id;
            in builtins.mapAttrs (_: wrapChild) raw
          else fn self id
        ) attributes
      ) roots;

      # Resolve a node by ID.
      # Roots: direct lookup. Non-roots: via parseParent or generic walk.
      resolveNode = id:
        if roots ? ${id} then roots.${id}
        else if parseParent != null then
          let
            parentId = parseParent id;
          in
          if parentId == null then genericResolve id
          else
            let
              children = self.get parentId "children";
              derived =
                if attributes ? "derived-children"
                then self.get parentId "derived-children"
                else {};
              all = children // derived;
            in
            if all ? ${id} then all.${id}
            else throw "gen-scope: node '${id}' not reachable (parent: ${parentId})"
        else genericResolve id;

      # Fallback resolution: walk from all roots through children.
      # O(n) worst case — use parseParent for production scale.
      genericResolve = id:
        let
          walkChildren = parentId:
            let
              children = self.get parentId "children";
              derived =
                if attributes ? "derived-children"
                then self.get parentId "derived-children"
                else {};
              all = children // derived;
            in
            if all ? ${id} then all.${id}
            else
              lib.foldl' (acc: childId:
                if acc != null then acc else walkChildren childId
              ) null (builtins.attrNames all);
          found = lib.foldl' (acc: rootId:
            if acc != null then acc else walkChildren rootId
          ) null (builtins.attrNames roots);
        in
        if found != null then found
        else throw "gen-scope: node '${id}' not reachable from roots";
    in {
      node = resolveNode;

      get = id: attrName:
        builtins.addErrorContext "evaluating '${attrName}' on '${id}'" (
          if !(attributes ? ${attrName}) then
            throw "gen-scope: unknown attribute '${attrName}' on node '${id}'"
          else if rootEval ? ${id} then rootEval.${id}.${attrName}
          else let n = self.node id;
          in if n ? _eval then n._eval.${attrName}
          else attributes.${attrName} self id  # fallback (shouldn't happen)
        );

      # Tier 2: materialized flat map (forces full tree, all memoized).
      # O(n) — each node computed once. Use for gen-graph queries, diagrams, fleet ops.
      allNodes = let
        walkFrom = id:
          let
            children =
              if attributes ? "children" then self.get id "children"
              else {};
            derived =
              if attributes ? "derived-children" then self.get id "derived-children"
              else {};
            all = children // derived;
          in [{ name = id; value = self.node id; }]
             ++ lib.concatMap walkFrom (builtins.attrNames all);
      in lib.listToAttrs (lib.concatMap walkFrom (builtins.attrNames roots));
    });

  # Diagnostic variant with shadow-stack cycle tracing.
  #
  # Uses attrset-based visited (O(1) cycle check) + parallel list for ordered
  # trace output. Cycles produce: "gen-scope: cycle: a.x -> b.x -> a.x"
  #
  # Trade-off: defeats Nix's native memoization — every get call creates a
  # new self with updated visited/traceList. Use eval for production.
  evalDebug =
    {
      roots,
      attributes,
      parseParent ? null,
    }:
    let
      mkSelf = visited: traceList: {
        node = id:
          if roots ? ${id} then roots.${id}
          else if parseParent != null then
            let
              parentId = parseParent id;
              s = mkSelf visited traceList;
              children = if parentId != null then s.get parentId "children" else {};
              derived =
                if parentId != null && attributes ? "derived-children"
                then s.get parentId "derived-children"
                else {};
            in (children // derived).${id}
              or (throw "gen-scope: node '${id}' not reachable")
          else throw "gen-scope: evalDebug requires parseParent for non-root nodes";

        get = id: attrName:
          let
            traceEntry = "${id}.${attrName}";
          in
          if !(attributes ? ${attrName}) then
            throw "gen-scope: unknown attribute '${attrName}' on node '${id}'"
          else if visited ? ${traceEntry} then
            throw "gen-scope: cycle detected: ${builtins.concatStringsSep " -> " (traceList ++ [ traceEntry ])}"
          else
            attributes.${attrName}
              (mkSelf (visited // { ${traceEntry} = true; }) (traceList ++ [ traceEntry ]))
              id;

        allNodes = throw "gen-scope: evalDebug does not support allNodes (use eval for materialization)";
      };
    in mkSelf {} [];
in
{
  inherit eval evalDebug;
}
