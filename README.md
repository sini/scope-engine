# gen-scope

Demand-driven Higher-Order Attribute Grammar evaluator over algebraic scope graphs, implemented as a pure Nix library.

gen-scope is a **hybrid HOAG/RAG** evaluator: Higher-Order Attribute Grammars (Vogt et al., 1989) for dynamic node synthesis, Reference Attribute Grammars (Hedin, 2000) for cross-node references via import edges. It leverages Nix's native lazy evaluation for attribute computation, memoization, and cycle detection — we do not build an AG evaluator, Nix **is** the evaluator.

gen-scope is generic. It has no knowledge of NixOS, aspects, policies, or system configuration. It provides evaluation machinery; consumers define what to compute.

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
| [gen](https://github.com/sini/gen) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |

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

Returns `{ node, get, allNodes }`:

| Function | Cost | Description |
|----------|------|-------------|
| `result.node id` | O(1) root, O(depth) synth | Resolve node structural data |
| `result.get id attrName` | O(1) amortized | Demand-driven attribute access (memoized) |
| `result.allNodes` | O(n) | Tier 2: flat map of all reachable nodes |

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

Four core primitives (Mokhov, 2017):

| Function | Signature | Description |
|----------|-----------|-------------|
| `empty` | `graph` | Empty graph |
| `vertex` | `string → graph` | Single vertex |
| `overlay` | `graph → graph → graph` | Union |
| `connect` | `graph → graph → graph` | Overlay + cross-product edges |

Derived: `overlays`, `vertices`, `edge`, `edges`, `path`, `circuit`, `star`, `clique`, `tree`, `forest`, `gmap`, `induce`, `transpose`, `removeVertex`, `removeEdge`, `hasVertex`, `hasEdge`.

### Attribute Combinators

#### `inherit'`

```nix
inherit' { resolve; _visited ? {}; } self id
```

Walks parent chain until `resolve node` returns non-null. Cycle-safe.

#### `inheritAll`

```nix
inheritAll { extract; combine ? a: b: a ++ b; } self id
```

Accumulates values along entire parent chain.

#### `circular`

```nix
circular { init; eq ? a: b: a == b; maxIter ? 100; } f self id
```

Fixed-point iteration. `f` receives `self`, `id`, and previous value.

#### `collectionAttr`

```nix
collectionAttr { traverse; extract; combine ? a: b: a ++ b; filter ? _: true; } self id
```

Traverse modes: `"imports"`, `"children"`, `"siblings"`, `"ancestors"`, `"label:<name>"`, or custom function.

#### `query`

```nix
query { dataFilter; localShadowsImport ? true; importShadowsParent ? true; transitiveImports ? false; } self id
```

Neron (2015) resolution: searches local → imports → parent with specificity D < I < P.

#### `queryAll`

```nix
queryAll { dataFilter; transitiveImports ? false; } self id
```

All reachable results without shadowing. For ambiguity detection.

#### `paramAttr`

```nix
paramAttr f self id param
```

Parameterized attribute (Sloane 2010 §3).

#### Other

- `shadow inner outer` — inner shadows outer (key-based)
- `resolve { local?, imported?, inherited? }` — specificity-ordered
- `collectImports extract self id` — collect from imported scopes
- `collect { filter? } extract self` — global collection (Tier 2)
- `collectByType type extract self` — filter by node type (Tier 2)
- `followEdge label self id` — custom edge label targets
- `collectByLabel label extract self id` — collect via custom edges
- `subtypeOf { eq? } self idA idB` — structural subtyping
- `ambiguous args self id` — multiple reachable declarations?
- `visibleFrom dataFilter self id` — single visible declaration

### Structural Queries

Thin wrappers over `self.node` and `self.get`:

| Function | Source | Description |
|----------|--------|-------------|
| `parent self id` | `(self.node id).parent` | Parent node ID |
| `children self id` | `self.get id "children"` | Child nodes attrset |
| `childrenIds self id` | `attrNames (self.get ...)` | Child node IDs |
| `ancestors self id` | Parent chain walk | All ancestors |
| `siblings self id` | Parent's other children | Sibling IDs |
| `descendants self id` | Recursive children walk | All descendants |
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

**`parseParent` is mandatory for fleet scale.** Without it, node resolution walks from ALL roots per unknown node. For 500 roots × 1500 synthesized nodes = 750,000 root checks. With `parseParent`: 1500 × O(1) = 1500.

## Testing

```bash
cd templates/ci
just ci              # run all tests
just ci eval         # run eval suite
just ci eval.test-basic-root-attribute  # specific test
```

Requires nix-unit. 120+ tests across 10 suites.

## Theoretical Foundations

| Paper | Used for |
|-------|----------|
| Vogt et al. (1989) "Higher-order attribute grammars" | Dynamic node synthesis via `children`/`derived-children` |
| Hedin (2000) "Reference attributed grammars" | Cross-node references, import edges |
| Hedin & Magnusson (2003) "JastAdd" | Demand-driven evaluation, aspect-oriented extension |
| Neron et al. (2015) "A theory of name resolution" | Scope graphs, resolution calculus, shadow, well-formedness |
| van Antwerpen et al. (2018) "Scopes as types" | Generalized queries, structural subtyping, custom edge labels |
| Mokhov (2017) "Algebraic graphs with class" | Graph construction primitives |
| Mokhov et al. (2018) "Build systems à la carte" | Demand-driven evaluation = suspending scheduler |
| Sloane et al. (2010) "Kiama" | CachedAttribute pattern, paramAttr, circular attributes |
| Radul & Sussman (2009) "Art of the propagator" | Monotonic cells, partial information |
| Van Wyk et al. (2010) "Silver" | Forwarding, collection attributes |

## License

MIT
