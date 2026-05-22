# Nest Traits

Nest's CSS-inspired traits model rebuilt on scope-engine, gen-schema, and gen-aspects. Demonstrates that nest's evaluation engine decomposes cleanly into three independent libraries, each handling one concern.

## What it demonstrates

Infrastructure nodes live in a hierarchical DOM. Traits are composable tags with forward dependencies (`needs`), reverse injection (`neededBy`), and synthesis (`synth`). Rules match nodes via CSS-style selectors and contribute class-keyed configuration. A 5-phase pipeline resolves everything into typed outputs.

```
trait definitions                  DOM hierarchy              rules
─────────────────                  ─────────────              ─────
host (class: nixos)                prod/                      host → boot config
server (needs: ssh)                  lb (host, lb, server)    server → openssh
monitoring (neededBy: server)        web-1 (host, web, server)  lb → haproxy backends
user (class: homeManager)              alice (user, admin)    host:has(admin) → sudo
                                     web-2 (host, web, server)  user → git config
                                       bob (user)
```

The pipeline walks the DOM, expands trait dependencies, runs synthesis, matches rules via selectors, and produces typed outputs grouped by class:

```nix
result = nest.evalNest {
  trait = { host = hostT; server = serverT; monitoring = monitoringT; ... };
  rules = [
    { is = hostT; nixos = { boot.loader.grub.enable = true; }; }
    { is = lbT;   nixos = { select, ... }: {
        services.haproxy.backends = map (w: w.name) (select webT);
      };
    }
    { is = [ hostT (sel.has adminT) ]; nixos = { security.sudo.enable = true; }; }
  ];
  prod = {
    lb    = { is = [ hostT lbT serverT ]; };
    web-1 = { is = [ hostT webT serverT ]; users.alice = { is = [ userT adminT ]; }; };
    web-2 = { is = [ hostT webT serverT ]; users.bob   = { is = [ userT ]; }; };
  };
};
# → { outputs = { lb = ...; web-1 = ...; alice = ...; }; byClass = { nixos = {...}; homeManager = {...}; }; }
```

## Three-layer architecture

Each library handles one concern:

| Layer | Library | Role |
|---|---|---|
| **Type definitions** | gen-schema | Trait sidecars (`needs`, `neededBy`, `synth`, `class`), node instance registry, ref validation |
| **Rule content** | gen-aspects | Class-separated `deferredModule` output via `aspectsType`, `is` selector injected via `aspectModules` |
| **Graph evaluation** | scope-engine | DOM hierarchy as parent edges, structural queries (`childrenIds`, `ancestors`, `siblings`), `buildNodes` for graph construction |

Template-local code provides the CSS selector engine and the 5-phase evaluation pipeline.

## Evaluation pipeline

### Phase 1: DOM traversal + trait expansion

`walkDom` recursively walks the input attrset. Nodes are identified by having an `is` field (a list of traits). Namespace folders (attrsets without `is`) propagate their scalar attributes downward as inherited context.

After collecting nodes, trait `needs` chains are expanded via BFS with seen-set dedup (handles diamond and circular dependencies). Then `neededBy` runs reverse injection — each entry is an independent selector (OR semantics), and matching nodes receive the trait.

### Phase 2: Trait synth

Entity traits (those with a `class` sidecar) can declare `synth` — a list of functions that derive node attributes and inject virtual children. Functions are folded in order, results deep-merged.

### Phase 3: Rule annotation

Rules are matched against each node using the CSS selector engine. Matching rules contribute class-keyed configuration collected as lists (preserving NixOS module system merge semantics). `synth` keys are deep-merged separately.

### Phase 4: Rule synth

Rule-level `synth` results produce derived attributes and virtual children. New children are re-annotated against all rules so they participate in output processing.

### Phase 5: Output processing

Each node with an entity trait calls its class function (`classFn select modules`) and produces a named output. Results are collected into `{ outputs, byClass }`.

## Selector engine

Full port of nest's CSS selector matching. Supports:

| Selector | Syntax | Meaning |
|---|---|---|
| Trait | `hostTrait` | Node's `is` list contains this trait |
| Star | `*` | Matches any node |
| ID | `#web-1` | Node name matches |
| Class | `.nixos` | Entity trait exposes this output class |
| Attr | `[env=prod]` | Node attribute matches value |
| Attr exists | `[system]` | Node has this attribute |
| AND | `[sel1, sel2]` | List = all must match |
| OR | `sel1,sel2` | CSS comma = any can match |
| Not | `:not(sel)` | Node does not match |
| Has | `:has(sel)` | Direct child matches |
| Within | `:within(sel)` | Some ancestor matches |
| When | `:when(fn)` | Arbitrary predicate |
| Child | `parent > child` | Direct parent matches left, node matches right |
| Descendant | `ancestor + desc` | Some ancestor matches left, node matches right |

Selectors can be trait references, programmatic constructors, or CSS strings — all three can be mixed freely.

## File structure

```
templates/nest-traits/
├── flake.nix              # inputs: scope-engine, gen-schema, gen-aspects, gen, nixpkgs
├── lib/
│   ├── default.nix        # public API: evalNest, selectors, walkDom, trait helpers
│   ├── engine.nix         # 5-phase evaluation pipeline
│   ├── selectors.nix      # CSS selector matching (matchesOne, mkCtx, mkCtxFromGraph)
│   ├── css.nix            # CSS string parser (parseCssSel, parseCompound)
│   ├── dom.nix            # DOM traversal (walkDom) + scope-engine graph (buildDomGraph)
│   ├── traits.nix         # trait expansion (expandTraits, expandNeededBy, applySynth)
│   └── setup.nix          # gen-schema/gen-aspects integration helpers
└── tests.nix              # 71 tests across 8 suites
```

## Defining traits

Traits are plain attrsets with a `__traitName` and optional special keys:

```nix
hostTrait = {
  __traitName = "host";
  class.nixos = select: modules: nixosSystem { inherit modules; };
  synth = [
    ({ select, ... }: { node.userCount = builtins.length (select.children userTrait); })
  ];
};

serverTrait = {
  __traitName = "server";
  needs = [ sshTrait firewallTrait ];        # forward dependencies
};

monitoringTrait = {
  __traitName = "monitoring";
  neededBy = [ serverTrait ];                # auto-inject into matching nodes
};
```

| Key | Type | Purpose |
|---|---|---|
| `__traitName` | string | Identity for dedup and selector matching |
| `class` | `{ className = select: modules: value; }` | Output builder — defines what class this entity produces |
| `needs` | `[traits]` or `traits: [traits]` | Forward dependency chain (BFS expanded) |
| `neededBy` | `[selectors]` | Reverse injection — each entry matched independently (OR) |
| `synth` | `[fns]` | Synthesis functions — derive attrs, inject virtual children |

## Defining rules

Rules match nodes via selectors and contribute class-keyed configuration:

```nix
rules = [
  # Static config
  { is = hostTrait; nixos = { boot.loader.grub.enable = true; }; }

  # Dynamic config via select
  { is = lbTrait; nixos = { select, ... }: {
      services.haproxy.backends = map (w: w.name) (select webTrait);
    };
  }

  # Compound selector (AND)
  { is = [ hostTrait (sel.has adminTrait) ]; nixos = { security.sudo.enable = true; }; }

  # CSS string selector
  { is = "#web-1[env=prod]"; nixos = { ... }; }
];
```

Class-keyed values are collected as lists (not deep-merged) to preserve NixOS module system semantics (`lib.mkForce`, `lib.mkDefault`, etc.).

## Tests

71 tests across 8 suites:

| Suite | Tests | What it covers |
|---|---|---|
| `smoke` | 2 | Library loads, exports present |
| `css` | 12 | CSS string parser: all token types, combinators, compound selectors |
| `dom` | 9 | DOM walk, namespace inheritance, overrides, nesting, scope-engine graph |
| `selectors` | 17 | All 12 selector handlers, CSS integration, `callWithArgs` |
| `traits` | 8 | Needs BFS, diamond dedup, circular safety, neededBy OR dispatch, needs-as-function |
| `engine-tests` | 8 | Full pipeline: basic output, byClass, rule matching, needs/neededBy in pipeline, list collection, `:has` selector |
| `demo` | 10 | Fleet scenario: lb + web nodes + users, cross-node select, sudo via `:has(admin)`, homeManager routing, neededBy monitoring |
| `edge-cases` | 5 | Empty DOM, marker-only traits, CSS selectors in rules, deep nesting, multiple same-level nodes |

```bash
nix run github:nix-community/nix-unit -- --flake .#tests
```

## Relationship to nest

This template is a proof-of-concept that nest's evaluation engine can be decomposed into gen-schema + gen-aspects + scope-engine. The `evalNest` API accepts the same `{ trait, rules, ...dom }` shape as nest's `evalNest`, and the selector engine is a direct port.

Key differences from nest:

- **`synth` is a list** (nest uses a single function) — enables multi-module composition
- **`neededBy` entries are OR-dispatched** — each selector is independent, `++` merge across modules composes correctly
- **Structural queries use scope-engine** — `buildDomGraph` creates a pre-indexed node map, `mkCtxFromGraph` uses `childrenIds`/`ancestors`/`siblings` for O(1) lookups
- **gen-schema integration** — `setup.nix` provides `mkTraitSchema` and `evalNestModules` for module-system-based trait/rule definitions with sidecar extraction and validation
- **gen-aspects integration** — `mkRulesType` creates an `aspectsType` with class-separated `deferredModule` output and `is` injected via `aspectModules`

## References

- [nest](https://github.com/denful/nest) — the original CSS-inspired infrastructure framework
- [scope-engine](https://github.com/sini/scope-engine) — demand-driven HOAG evaluator over algebraic scope graphs
- [gen-schema](https://github.com/sini/gen-schema) — typed record registries with sidecars, refs, and validation
- [gen-aspects](https://github.com/sini/gen-aspects) — aspect-oriented composition types (Palmer flat dispatch)
