# gen-scope

[![CI](https://github.com/sini/gen-scope/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-scope/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Demand-driven Higher-Order Attribute Grammar evaluator over algebraic scope graphs, implemented as a pure Nix library.

gen-scope is a **hybrid HOAG/RAG** evaluator: Higher-Order Attribute Grammars (Vogt et al., 1989) for dynamic node synthesis, Reference Attribute Grammars (Hedin, 2000) for cross-node references via import edges. It leverages Nix's native lazy evaluation for attribute computation, memoization, and cycle detection — we do not build an AG evaluator, Nix **is** the evaluator.

gen-scope is generic. It has no knowledge of NixOS, aspects, policies, or system configuration. It provides evaluation machinery; consumers define what to compute.

## Table of Contents

- [Core Insight](#core-insight)
- [Terminology](#terminology)
- [Gen Ecosystem](#gen-ecosystem)
- [Usage](#usage)
- [Example](#example)
- [HOAG: Dynamic Tree Expansion](#hoag-dynamic-tree-expansion)
- [API Reference](#api-reference)
  - [eval](#eval)
  - [evalDebug](#evaldebug)
  - [buildNodes](#buildnodes)
  - [Algebraic Graph Construction](#algebraic-graph-construction)
  - [Attribute Combinators](#attribute-combinators)
  - [Structural Queries](#structural-queries)
- [Performance](#performance)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Core Insight

Nix attrset VALUES are lazy but KEYS are eager. Function application is never memoized. The only way to get O(1) attribute access is an attrset entry.

**The solution:** Co-locate the memoization cache (`_eval`) ON each node. When a parent's `children` attribute materializes child nodes, each child is wrapped with `_eval` — a lazy attrset of that child's attribute computations. The cache is distributed across the tree, not centralized.

## Terminology

| Term | Definition |
|------|-----------|
| Nodes | Minimal descriptors: `{ id, type, parent, decls }` |
| Roots | Entry-point nodes (from `buildNodes` or hand-written) |
| Children | Synthesized nodes produced by the `children` attribute |
| Derived Children | Synthesized nodes from `derived-children` (can read sibling attrs) |
| Attributes | Computed values on nodes — demand-driven, memoized via `_eval` |
| Combinators | Attribute constructors: `inherit'`, `circular`, `paramAttr`, `collectionAttr`, `query` |
| Tier 1 | Navigation: `self.node id`, `self.get id attrName` — O(1) or O(depth) |
| Tier 2 | Materialization: `self.allNodes` — O(n), forces full tree |

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject args into NixOS modules) |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch (stratified phases, fixpoint, conflict resolution) |

## Usage

```nix
# flake.nix
{
  inputs.gen-scope.url = "github:sini/gen-scope";
  outputs = { gen-scope, nixpkgs, ... }:
    let engine = gen-scope { lib = nixpkgs.lib; };
    in { /* ... */ };
}

# Or without flakes:
let engine = import ./gen-scope { inherit lib; };
in { /* ... */ }
```

## Example

A hierarchical configuration: environments contain hosts, hosts inherit environment config.

```nix
let
  engine = import ./gen-scope { inherit lib; };

  roots = engine.buildNodes {
    parentGraph = engine.overlay
      (engine.star "env:prod" [ "host:web" "host:db" ])
      (engine.star "env:dev" [ "host:dev" ]);
    decls = {
      "env:prod" = { region = "us-east"; isHighSec = true; };
      "env:dev"  = { region = "eu-west"; isHighSec = false; };
      "host:web" = { role = "frontend"; };
      "host:db"  = { role = "database"; };
      "host:dev" = { role = "all"; };
    };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      # Tree stays flat — no children synthesis in this example
      children = _self: _id: {};

      # Inherited: walks parent chain
      region = engine.inherit' { resolve = n: n.decls.region or null; };

      # Synthesized: computed from node data
      greeting = self: id:
        "hello ${id} in ${self.get id "region"}";
    };
  };
in {
  webRegion = result.get "host:web" "region";     # "us-east"
  webGreeting = result.get "host:web" "greeting"; # "hello host:web in us-east"
  devRegion = result.get "host:dev" "region";     # "eu-west"
}
```

## HOAG: Dynamic Tree Expansion

The `children` attribute synthesizes new nodes on demand. Attribute-dependent — can read other attributes to decide what to create:

```nix
let
  roots = {
    "env:prod" = {
      id = "env:prod"; type = "env"; parent = null;
      decls = { hosts = [ "web-1" "db-1" ]; isHighSec = true; };
    };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      is-high-sec = self: id: (self.node id).decls.isHighSec or false;

      # Children depend on is-high-sec attribute
      children = self: id:
        let n = self.node id; in
        if n.type == "env" then
          lib.listToAttrs (map (h: {
            name = "host:${h}@${id}";
            value = {
              id = "host:${h}@${id}"; type = "host"; parent = id;
              decls = {
                users = [ "root" ] ++ lib.optional (self.get id "is-high-sec") "auditor";
              };
            };
          }) (n.decls.hosts or []))
        else if n.type == "host" then
          lib.listToAttrs (map (u: {
            name = "user:${u}@${id}";
            value = { id = "user:${u}@${id}"; type = "user"; parent = id; decls = {}; };
          }) (n.decls.users or []))
        else {};

      # Inherited security propagates through synthesized nodes
      inherited-sec = self: id:
        let n = self.node id; in
        if n.decls ? isHighSec then n.decls.isHighSec
        else if n.parent != null then self.get n.parent "inherited-sec"
        else false;
    };
    parseParent = id:
      let parts = lib.splitString "@" id; in
      if builtins.length parts > 1 then lib.concatStringsSep "@" (lib.drop 1 parts)
      else null;
  };
in {
  # Auditor user only on prod (attribute-dependent synthesis)
  prodUsers = builtins.attrNames (result.get "host:web-1@env:prod" "children");
  # → [ "user:auditor@host:web-1@env:prod" "user:root@host:web-1@env:prod" ]

  auditorSec = result.get "user:auditor@host:web-1@env:prod" "inherited-sec";
  # → true
}
```

### `derived-children` — Second-Stage Synthesis

`derived-children` can read attributes of nodes produced by `children` (Vogt 1989 §2.4 NTA stratification):

```nix
attributes = {
  children = self: id: { ... };
  derived-children = self: id:
    let alice = self.get "user:alice@${id}" "resolved-aspects"; in
    if hasAspect "sudo" alice
    then { "user:alice-admin@${id}" = { ... }; }
    else {};
};
```

## API Reference

### `eval`

```nix
eval {
  roots;               # { id = { id, type, parent, decls }; }
  attributes;          # { attrName = self: id: value; }
  parseParent ? null;  # id → parentId | null
}
```

Returns `{ node, get, allNodes, allNodesWhere, subtreeOf, nodesOfType }`:

| Function | Cost | Description |
|----------|------|-------------|
| `result.node id` | O(1) root, O(depth) synth | Resolve node structural data |
| `result.get id attrName` | O(1) amortized | Demand-driven attribute access (memoized) |
| `result.allNodes` | O(n) | Tier 2: flat map of all reachable nodes |
| `result.allNodesWhere pred` | O(n) | Tier 2: selective materialization filtered by predicate on node data |
| `result.subtreeOf rootId` | O(subtree) | Tier 2: materialize only the subtree rooted at a given node |
| `result.nodesOfType type` | O(n) | Tier 2: all nodes matching a given type string |

**Special attributes:** `children` and `derived-children` are auto-wrapped — their results are node attrsets where each child receives a co-located `_eval` cache.

### `evalDebug`

Same interface as `eval`. Provides structured cycle traces instead of Nix's opaque "infinite recursion." Trade-off: defeats memoization. Use for diagnosing cycles only.

### `buildNodes`

```nix
buildNodes {
  parentGraph ? empty;   # Algebraic graph for P edges (child → parent)
  importGraph ? empty;   # Algebraic graph for I edges
  edgeGraphs ? {};       # Custom labeled edges: { label → graph }
  decls ? {};            # { nodeId → attrset }
  types ? {};            # { nodeId → string }
  strict ? true;         # true: deepSeq validates parent uniqueness upfront
}
```

Returns minimal root descriptors: `{ id = { id, type, parent, decls }; }`.

Edge data is stored in `decls.__edges`: `{ I = [...]; customLabel = [...]; }`. Consumers define attributes to interpret these edges:

```nix
attributes = {
  imports = self: id: (self.node id).decls.__edges.I or [];
  children = self: id: {};
};
```

### Algebraic Graph Construction

Four core primitives (Mokhov, 2017 §2.1):

| Function | Signature | Description |
|----------|-----------|-------------|
| `empty` | `graph` | Empty graph |
| `vertex` | `string → graph` | Single vertex |
| `overlay` | `graph → graph → graph` | Union (commutative, associative, idempotent) |
| `connect` | `graph → graph → graph` | Overlay + cross-product edges |

Derived constructors (Mokhov, 2017 §2.2, §5.1):

| Function | Description |
|----------|-------------|
| `overlays` | Fold overlay over list of graphs |
| `vertices` | List of isolated vertices |
| `edge` | Single edge from two vertex IDs |
| `edges` | List of `{ from, to }` records |
| `path` | Sequential chain of edges |
| `circuit` | Cycle connecting last to first |
| `star` | Center vertex with leaf edges (inverted: leaves point to center) |
| `clique` | Fully connected subgraph |
| `tree` | Recursive `{ root, children }` structure |
| `forest` | List of trees |

Graph transformations (Mokhov, 2017 §5.2-5.5):

| Function | Description |
|----------|-------------|
| `gmap` | Map function over vertices |
| `induce` | Subgraph matching predicate |
| `transpose` | Flip all edge directions |
| `hasVertex` | Vertex membership test |
| `hasEdge` | Edge membership test |
| `removeVertex` | Remove vertex and incident edges |
| `removeEdge` | Remove a single edge |

### Attribute Combinators

#### `inherit'`

```nix
inherit' { resolve; _visited ? {}; } self id
```

Walks parent chain until `resolve node` returns non-null. Cycle-safe via `_visited`.

#### `inheritAll`

```nix
inheritAll { extract; combine ? a: b: a ++ b; } self id
```

Accumulates values along entire parent chain.

#### `circular`

```nix
circular { init; eq ? a: b: a == b; maxIter ? 100; } f self id
```

Fixed-point iteration (Sloane 2010 §2.2). `f` receives `self`, `id`, and previous value.

#### `collectionAttr`

```nix
collectionAttr { traverse; extract; combine ? a: b: a ++ b; filter ? _: true; } self id
```

Traverse modes: `"imports"`, `"children"`, `"siblings"`, `"ancestors"`, `"label:<name>"`, or custom function.

#### `query`

```nix
query { dataFilter; localShadowsImport ? true; importShadowsParent ? true; transitiveImports ? false; } self id
```

Neron (2015) resolution: searches local, imports, parent with specificity D < I < P. Import edges come from `self.get id "imports"` (computed attribute). `_seen` tracks visited scopes to prevent import self-resolution (Neron 2015 §2.4, rule X).

#### `queryAll`

```nix
queryAll { dataFilter; transitiveImports ? false; } self id
```

All reachable results without shadowing (Neron 2015 §2.3, rule R). For ambiguity detection.

#### `paramAttr`

```nix
paramAttr f self id param
```

Parameterized attribute (Sloane 2010 §3).

#### Other Combinators

| Function | Description |
|----------|-------------|
| `shadow inner outer` | Inner shadows outer by key (Neron 2015 §5 Def. 1) |
| `resolve { local?, imported?, inherited? }` | Specificity-ordered resolution (Neron 2015 Fig. 2) |
| `collectImports extract self id` | Collect from imported scopes (Neron 2015 §2.4, rule I) |
| `collect { filter? } extract self` | Global collection (Tier 2, forces `allNodes`) |
| `collectByType type extract self` | Filter by node type (Tier 2) |
| `followEdge label self id` | Custom edge label targets (van Antwerpen 2018 §2.1) |
| `collectByLabel label extract self id` | Collect via custom edges |
| `subtypeOf { eq? } self idA idB` | Structural subtyping (van Antwerpen 2018 §2.3) |
| `ambiguous args self id` | Multiple reachable declarations? (van Antwerpen 2018 §2.3) |
| `visibleFrom dataFilter self id` | Single visible declaration from a scope |

### Structural Queries

Thin wrappers over `self.node` and `self.get`:

| Function | Source | Description |
|----------|--------|-------------|
| `parent self id` | `(self.node id).parent` | Parent node ID |
| `children self id` | `self.get id "children"` | Child nodes attrset |
| `childrenIds self id` | `attrNames (self.get ...)` | Child node IDs |
| `ancestors self id` | Parent chain walk | All ancestor IDs (cycle-safe) |
| `siblings self id` | Parent's other children | Sibling IDs |
| `descendants self id` | Recursive children walk | All descendant IDs (cycle-safe) |
| `isAncestor self ancestorId id` | `elem` check | Whether `ancestorId` is an ancestor of `id` |
| `isDescendant self descendantId id` | `elem` check | Whether `descendantId` is a descendant of `id` |
| `nodesByType self type` | `self.allNodes` filter | Nodes by type (Tier 2) |

## Performance

| Operation | Cost | Memoized? |
|-----------|------|-----------|
| `self.get rootId attrName` | O(1) | Yes — `rootEval.${id}.${attrName}` |
| `self.get synthId attrName` | O(depth) first, O(1) after | Yes — `node._eval.${attrName}` |
| `self.node rootId` | O(1) | Yes — direct roots lookup |
| `self.node synthId` (with parseParent) | O(depth) | Via parent's memoized children |
| `self.node synthId` (generic fallback) | O(n) | Via memoized children along path |
| `self.allNodes` | O(n) | Each node computed once |

**`parseParent` is mandatory for fleet scale.** Without it, node resolution walks from ALL roots per unknown node. For 500 roots x 1500 synthesized nodes = 750,000 root checks. With `parseParent`: 1500 x O(1) = 1500.

## Testing

```bash
cd ci
just ci              # run all tests
just ci eval         # run eval suite
just ci eval.test-basic-root-attribute  # specific test
```

Requires nix-unit. 120+ tests across 10 suites.

## Theoretical Foundations

| Paper | Relationship | Used for |
|-------|-------------|----------|
| Vogt et al. (1989) "Higher-order attribute grammars" | **Implements** | Dynamic node synthesis via `children`/`derived-children` as non-terminal attributes (§2.4); `derived-children` extends this with second-stage stratification |
| Hedin (2000) "Reference attributed grammars" | **Implements** | Import edges as reference attributes; cross-node attribute access via computed scope references |
| Hedin & Magnusson (2003) "JastAdd" | **Informed by** | Demand-driven evaluation pattern; aspect-oriented attribute extension model |
| Neron et al. (2015) "A theory of name resolution" | **Implements** | Scope graph construction, resolution calculus (`query`/`queryAll`), D < I < P specificity ordering (Fig. 2), well-formedness of paths (§2.4), seen-imports cycle prevention (rule X), shadowing (§5 Def. 1) |
| van Antwerpen et al. (2018) "Scopes as types" | **Implements** | Custom edge labels via `edgeGraphs`/`followEdge`, structural subtyping (`subtypeOf`), generalized queries with per-query visibility policies, Statix-style constraint patterns |
| Mokhov (2017) "Algebraic graphs with class" | **Implements** | All four graph construction primitives (`empty`/`vertex`/`overlay`/`connect`) and derived constructors (`star`/`path`/`clique`/`tree`/etc.) from §2.1-§5.1 |
| Sloane et al. (2010) "Kiama: AG embedding" | **Implements** | `CachedAttribute` pattern realized as `_eval` co-located cache; `paramAttr` (§3); `circular` fixed-point attributes (§2.2); collection attributes (§7) |
| Radul & Sussman (2009) "Art of the propagator" | **Informed by** | Monotonic convergence concept for `circular` attribute iteration; cells accepting information from multiple sources as design influence on scope graph merging |
| Van Wyk et al. (2010) "Silver: extensible AG" | **Informed by** | Forwarding concept (productions defining default attribute values via translation); collection attributes with fold operators as design influence on `collectionAttr` |
| Mokhov et al. (2018) "Build systems a la carte" | **Informed by** | Demand-driven evaluation as suspending scheduler (§4.1); Nix's lazy evaluation recognized as the scheduling mechanism — we do not build a scheduler, Nix is the scheduler |
