# scope-engine

Demand-driven attribute grammar evaluator over algebraic scope graphs, implemented as a pure Nix library.

scope-engine is a **hybrid HOAG/RAG** evaluator: Higher-Order Attribute Grammars (Vogt et al., 1989) for dynamic node synthesis, Reference Attribute Grammars (Hedin, 2000) for cross-node references via import edges. It leverages Nix's native lazy evaluation for attribute computation, memoization, and cycle detection — we do not build an AG evaluator, Nix **is** the evaluator.

scope-engine is generic. It has no knowledge of NixOS, aspects, policies, or system configuration. It provides evaluation machinery; consumers define what to compute.

## Usage

```nix
# flake.nix
{
  inputs.scope-engine.url = "github:sini/scope-engine";
  outputs = { scope-engine, nixpkgs, ... }:
    let
      engine = scope-engine { lib = nixpkgs.lib; };
    in { /* ... */ };
}

# Or without flakes:
let
  engine = import ./scope-engine { inherit lib; };
in { /* ... */ }
```

## Example

A hierarchical configuration system: departments contain teams, teams inherit department config.

```nix
let
  engine = import ./scope-engine { inherit lib; };

  # Algebraic graph: departments → teams
  parentGraph = engine.overlay
    (engine.vertices [ "dept:eng" "dept:sales" ])
    (engine.overlay
      (engine.star "dept:eng" [ "team:platform" "team:frontend" ])
      (engine.edge "team:field" "dept:sales"));

  baseNodes = engine.buildNodes {
    inherit parentGraph;
    decls = {
      "dept:eng"      = { budget = 500000; location = "SF"; };
      "dept:sales"    = { budget = 200000; location = "NYC"; };
      "team:platform" = { size = 8; focus = "infra"; };
      "team:frontend" = { size = 5; focus = "ui"; };
      "team:field"    = { size = 12; focus = "enterprise"; };
    };
  };

  attributes = {
    # Inherited attribute: location flows top-down from department to team
    location = engine.inherit_ {
      resolve = node: node.decls.location or null;
    };

    # Synthesized attribute: headcount rolls up bottom-up from children
    headcount = self: id:
      let
        node = self.nodes.${id};
        local = node.decls.size or 0;
        childTotal = lib.foldl'
          (acc: cid: acc + (self.evaluated.${cid}.get "headcount"))
          0 node.childrenIds;
      in local + childTotal;
  };

  result = engine.eval { inherit baseNodes attributes; };
in {
  platformLocation = result.evaluated."team:platform".get "location";  # "SF"
  engHeadcount     = result.evaluated."dept:eng".get "headcount";      # 13
  salesHeadcount   = result.evaluated."dept:sales".get "headcount";    # 12
}
```

## API Reference

### Algebraic Graph Construction

Four core primitives (Mokhov, 2017) satisfy an algebra similar to a semiring. Overlay is commutative, associative, and idempotent. Connect distributes over overlay.

| Function | Signature | Description |
|---|---|---|
| `empty` | `graph` | Empty graph: no vertices, no edges |
| `vertex` | `string → graph` | Single-vertex graph |
| `overlay` | `graph → graph → graph` | Union of vertices and edges |
| `connect` | `graph → graph → graph` | Overlay + cross-product edges from left to right |

Derived constructors:

| Function | Signature | Description |
|---|---|---|
| `overlays` | `[graph] → graph` | Fold a list of graphs via overlay |
| `vertices` | `[string] → graph` | Isolated vertices |
| `edge` | `string → string → graph` | Single directed edge |
| `edges` | `[{from, to}] → graph` | Multiple edges from a list |
| `path` | `[string] → graph` | Sequential chain: `a → b → c` |
| `circuit` | `[string] → graph` | Path with back-edge from last to first |
| `star` | `string → [string] → graph` | Fan-in: all leaves connect to center |
| `clique` | `[string] → graph` | Fully connected subgraph |
| `tree` | `{root, children} → graph` | Recursive tree structure |
| `forest` | `[{root, children}] → graph` | Multiple trees |

Transformations:

| Function | Signature | Description |
|---|---|---|
| `gmap` | `(a → b) → graph → graph` | Map function over all vertex IDs |
| `induce` | `(string → bool) → graph → graph` | Subgraph matching predicate |
| `transpose` | `graph → graph` | Flip all edge directions |
| `removeVertex` | `string → graph → graph` | Remove a vertex and its edges |
| `removeEdge` | `string → string → graph → graph` | Remove a specific edge |
| `hasVertex` | `string → graph → bool` | Vertex membership test |
| `hasEdge` | `string → string → graph → bool` | Edge membership test |

### Scope Graph Construction

```nix
buildNodes {
  parentGraph;            # Algebraic graph for parent (P) edges — lexical nesting
  importGraph ? empty;    # Algebraic graph for import (I) edges — cross-scope visibility
  edgeGraphs ? {};        # Custom labeled edges: { label → algebraicGraph }
  decls ? {};             # { nodeId → attrset } — declarations per scope
  types ? {};             # { nodeId → string } — type tag per scope (e.g., "host", "user")
  relations ? {};         # { nodeId → { relName → data } } — multiple named relations
}
```

Returns a flat attrset of nodes. Each node has:

| Field | Type | Description |
|---|---|---|
| `id` | string | Node identifier |
| `type` | string or null | Type tag from `types` parameter |
| `parent` | string or null | Parent node ID (from P edges) |
| `imports` | [string] | Import target IDs (from I edges) |
| `decls` | attrset | Declarations for this scope |
| `rels` | attrset | All scoped relations including decls as `":"` |
| `childrenIds` | [string] | Child node IDs (reverse P edges) |
| `edgesByLabel` | { label → [string] } | All outgoing edges indexed by label |

`parentGraph` and `importGraph` are sugar for `edgeGraphs.P` and `edgeGraphs.I`. Custom edge labels (e.g., `R` for record fields, `E` for class extension) are passed via `edgeGraphs` and accessed via `edgesByLabel` on nodes.

### Scope Queries

Structural queries on the node map. These never trigger attribute evaluation — safe to call during HOAG synthesis.

| Function | Signature | Description |
|---|---|---|
| `parent` | `self → id → string?` | Parent node ID |
| `children` | `self → id → {id → node}` | Child nodes as attrset |
| `childrenIds` | `self → id → [string]` | Child node IDs |
| `ancestors` | `self → id → [string]` | All ancestors, nearest first |
| `siblings` | `self → id → [string]` | Sibling node IDs |
| `descendants` | `self → id → [string]` | All descendants, breadth-first |
| `isAncestor` | `self → ancestorId → id → bool` | Is `ancestorId` an ancestor of `id`? |
| `isDescendant` | `self → descendantId → id → bool` | Is `descendantId` a descendant of `id`? |
| `nodesByType` | `self → string → {id → node}` | All nodes matching a type tag |

### Resolution Primitives

Name resolution following Neron (2015) scope graph semantics and van Antwerpen (2018) generalized queries.

#### `shadow`

```nix
shadow = inner: outer: { ... }
```

Merge two declaration sets where inner shadows outer (Neron §5 Def. 1). Keys present in `inner` suppress the same keys from `outer`.

#### `resolve`

```nix
resolve {
  local ? null;                 # Declaration from the scope itself (D)
  imported ? null;              # Declaration from imported scopes (I)
  inherited ? null;             # Declaration from parent scope (P)
  localShadowsImport ? true;   # D < I specificity
  importShadowsParent ? true;  # I < P specificity
}
```

Specificity-ordered resolution (Neron Fig. 2). Default ordering: `D < I < P` — local declarations beat imports, imports beat parent scope. Override `localShadowsImport` or `importShadowsParent` for alternative policies like SML-style includes (Neron §2.5).

#### `query`

```nix
query {
  dataFilter;                   # node → value | null — extract data from a node
  labelWF ? "PI";               # "P", "I", or "PI" — which edge types to follow
  localShadowsImport ? true;    # Specificity policy
  importShadowsParent ? true;   # Specificity policy
  transitiveImports ? false;    # Follow imported scopes' own imports (P*.I*)
} self id
```

Generalized query combinator (van Antwerpen §2.1). Searches local declarations, imports, and parent chain according to the well-formedness predicate and specificity ordering. Returns the single visible result after shadowing, or `null`.

Tracks seen-imports internally to prevent self-resolution cycles (Neron §2.4, rule X).

#### `queryAll`

```nix
queryAll { dataFilter; labelWF ? "PI"; transitiveImports ? false; } self id
```

Returns **all** reachable results as a list without applying shadowing. Useful for ambiguity detection — when the list has more than one element, multiple declarations are reachable.

#### `ambiguous`

```nix
ambiguous { dataFilter; ... } self id  # → bool
```

Returns `true` when multiple declarations are reachable via `queryAll`. Built on `queryAll` for detecting shadowing ambiguity (van Antwerpen 2018).

### Named Attribute Constructors

Kiama-inspired vocabulary (Sloane et al., 2010) for self-documenting attribute definitions.

#### `inherit_`

```nix
inherit_ {
  resolve;             # node → value | null — extract data from a node
  allowParent ? true;  # Encode well-formedness P*.I* (Neron §2.4)
} self id
```

Inherited attribute: walks the parent chain until `resolve` returns non-null. When `allowParent` is `false`, stops after the current scope (for use after following an import edge — the `P*.I*` well-formedness condition).

#### `paramAttr`

```nix
paramAttr = f: self: id: param: f self id param;
```

Parameterized attribute (Sloane 2010 §3). The parameter becomes part of the thunk identity; Nix memoizes `(self, id, param)` naturally.

#### `circular`

```nix
circular {
  init;               # Initial value
  eq ? a: b: a == b;  # Convergence test
  maxIter ? 10;       # Iteration bound
} f self id
```

Fixed-point iteration from an initial value (Sloane 2010 §2.2). The attribute function `f` receives `self`, `id`, and the previous value, producing the next value. Iterates until `eq prev next` or `maxIter` is reached.

### Collection

| Function | Signature | Description |
|---|---|---|
| `collectImports` | `(self → id → [a]) → self → id → [a]` | Collect from imported scopes only (demand-driven) |
| `collect` | `{filter?} → (self → id → [a]) → self → [a]` | Collect from all nodes (global; prefer `collectImports`) |
| `collectByType` | `string → (self → id → [a]) → self → [a]` | Collect from nodes matching a type tag |
| `collectByLabel` | `string → (self → id → [a]) → self → id → [a]` | Collect from nodes reachable via a custom edge label |
| `followEdge` | `string → self → id → [string]` | Target node IDs for a custom edge label |

### Structural Subtyping

```nix
subtypeOf {
  eq ? _k: _a: _b: true;  # Per-key value comparison (default: key presence only)
} self idA idB  # → bool
```

Structural subtyping check (van Antwerpen §2.3): every key in scope A's declarations must exist in scope B's. Pass a custom `eq` function for value-level comparison.

### HOAG Evaluator

#### `eval`

```nix
eval {
  baseNodes;                   # Flat node map from buildNodes
  synthesize ? (_: {});        # HOAG function: self → { id → node }
  attributes;                  # { attrName = self: id: value; ... }
}
```

Returns `{ nodes, evaluated }`. Access results via `result.evaluated.${id}.get "attrName"`.

**`synthesize`** inspects the current graph and returns new nodes. Receives `{ nodes = baseNodes; evaluated; }` — it can read base node structure and demand attribute values, but cannot see its own synthesized output (monotone-add invariant). Synthesized nodes cannot overwrite base nodes.

**`attributes`** are named functions. Each can read any attribute on any node via `self.evaluated.${nodeId}.get "attrName"`. Evaluation is demand-driven: only attributes that are accessed get computed.

#### `evalDebug`

```nix
evalDebug { baseNodes; synthesize ? (_: {}); attributes; }
```

Diagnostic variant with shadow-stack cycle tracing. Same interface as `eval`, but threads a visited-set through `self` so that cycles produce structured error messages:

```
scope-engine: cycle detected: a.headcount -> b.headcount -> a.headcount
```

instead of Nix's opaque `infinite recursion encountered`.

**Trade-off:** defeats Nix's native memoization. The same `(id, attrName)` pair may be evaluated multiple times along different call paths. Use `eval` for production; `evalDebug` for diagnosing cycles.

## Advanced Examples

### Import Edges: Cross-Scope Data Flow

```nix
let
  importGraph = engine.edge "team:frontend" "team:platform";

  baseNodes = engine.buildNodes {
    inherit parentGraph importGraph;
    decls = {
      "team:platform" = { shared-tools = [ "terraform" "k8s" ]; };
    };
  };

  attributes = {
    available-tools = engine.collectImports
      (self: importId: self.nodes.${importId}.decls.shared-tools or []);
  };

  result = engine.eval { inherit baseNodes attributes; };
in
  result.evaluated."team:frontend".get "available-tools"
  # → [ "terraform" "k8s" ]
```

### HOAG: Dynamic Node Synthesis

Create review scopes for departments exceeding a budget threshold:

```nix
synthesize = self:
  let
    depts = lib.filterAttrs (id: _: lib.hasPrefix "dept:" id) self.nodes;
  in lib.concatMapAttrs (id: node:
    if (node.decls.budget or 0) > 300000 then {
      "review:${id}" = {
        inherit id; parent = id;
        decls = { reviewer = "finance"; threshold = 300000; };
        imports = []; childrenIds = []; type = "review";
      };
    } else {}
  ) depts;
```

### Custom Edge Labels

Model class inheritance with `E` (extension) edges:

```nix
baseNodes = engine.buildNodes {
  parentGraph = engine.vertices [ "classC" "classD" "classE" ];
  edgeGraphs = {
    E = engine.overlay
      (engine.edge "classD" "classC")
      (engine.edge "classE" "classD");
  };
  decls = {
    classC = { fieldF = 42; };
    classD = { fieldG = 99; };
    classE = { fieldH = 77; };
  };
};

# Follow E edges to collect inherited fields
allInherited = self: id:
  let
    parents = engine.followEdge "E" self id;
    direct = lib.concatMap (pid: builtins.attrNames self.nodes.${pid}.decls) parents;
    transitive = lib.concatMap (allInherited self) parents;
  in direct ++ transitive;
```

### Transitive Imports

By default, imports are non-transitive (`P*.I?`). Enable transitive imports for module systems where `import A` also brings in A's own imports:

```nix
engine.query {
  dataFilter = node: node.decls.value or null;
  transitiveImports = true;  # Follow A → B → C chains
} result "moduleA"
```

### SML-Style Includes

For `include` semantics where imported declarations have equal precedence with local declarations (no shadowing):

```nix
engine.query {
  dataFilter = node: node.decls.x or null;
  localShadowsImport = false;  # Local doesn't shadow import
} result "moduleB"
```

### Scoped Relations

Multiple named relations per scope for separate namespaces:

```nix
baseNodes = engine.buildNodes {
  parentGraph = engine.edge "inner" "outer";
  decls = { outer = { x = "value"; }; };
  relations = {
    outer = { typeDecl = { x = "Type_X"; }; };
  };
};

# Query value namespace
engine.query { dataFilter = n: n.decls.x or null; } result "inner"
# → "value"

# Query type namespace
engine.query { dataFilter = n: n.rels.typeDecl.x or null; } result "inner"
# → "Type_X"
```

## Testing

```bash
# Run all tests (requires nix-unit)
nix eval --override-input scope-engine . ./templates/ci#tests

# Run checks
nix flake check --override-input scope-engine . ./templates/ci
```

142 tests across 21 suites covering graph construction, scope resolution, inheritance, imports, HOAG synthesis, cycle detection, custom edge labels, ambiguity detection, and structural subtyping.

## Theoretical Foundations

| Paper | Used for |
|---|---|
| Knuth (1968) "Semantics of context-free languages" | Synthesized + inherited attributes |
| Vogt, Swierstra, Kuiper (1989) "Higher-order attribute grammars" | Dynamic node synthesis via `synthesize` |
| Hedin (2000) "Reference attributed grammars" | Cross-node references, fixed-point termination over import edges |
| Neron, Tolmach, Visser, Wachsmuth (2015) "A theory of name resolution" | Scope graphs, resolution calculus, shadow, well-formedness, seen-imports |
| van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018) "Scopes as types" | Scoped relations, per-query visibility policies, structural subtyping, custom edge labels |
| Mokhov (2017) "Algebraic graphs with class" | Graph construction primitives, algebraic laws, transformations |
| Mokhov, Mitchell, Peyton Jones (2018) "Build systems a la carte" | Demand-driven evaluation strategy, dynamic dependencies |
| Sloane, Kats, Visser (2010) "A pure OO embedding of attribute grammars" | CachedAttribute pattern, paramAttr, circular attributes |
| Sloane (2009) "Lightweight language processing in Kiama" | Host language laziness as AG evaluator |

## License

MIT
