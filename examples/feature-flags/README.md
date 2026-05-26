# Feature Flag Evaluator

Hierarchical feature flag resolution with environment scoping, flag dependencies, HOAG-synthesized rollout rules, and circular convergence.

## What it demonstrates

Flags are defined at hierarchy levels (global, org, project, user). Deeper levels override shallower ones. HOAG synthesis creates computed rollout tracking nodes. Circular attributes simulate iterative rollout convergence. Flag dependencies enforce prerequisites.

```
global                    dark-mode=false, new-editor=false, ai-assist=false, max-items=50
├── org:acme              dark-mode=true
│   ├── project:alpha     new-editor=true, max-items=100
│   │   ├── user:alice
│   │   └── user:bob      new-editor=false (opt-out)
│   └── project:beta
│       └── user:carol
└── org:widgets           beta-features=true
    └── project:gamma
        └── user:dave
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| `inherit'` / `query` | Neron 2015 §2.3 | Flag values inherited down the hierarchy |
| `shadow` | Neron 2015 §5 | User-level overrides shadow project/org/global |
| HOAG synthesis | Vogt 1989 | Rollout tracking nodes for beta-enabled orgs |
| `circular` | Sloane 2010 §2.2 | Rollout percentage convergence (0 -> 25 -> 50 -> 75 -> 100) |
| `paramAttr` | Sloane 2010 §3 | Flag lookup, flag-with-dependencies, override counting |
| `isAncestor` | -- | Verify user-to-org containment |
| `nodesByType` | -- | Find all users, orgs, rollout nodes |
| `childrenIds` | -- | List projects in an org, users in a project |

## Tests

27 tests covering: flag resolution at all hierarchy levels, user opt-out override, flag dependencies (ai-assist requires new-editor), effective flag merging, override counting, HOAG rollout synthesis, circular convergence, typed queries, and structural ancestor verification.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- Vogt, Swierstra, Kuiper (1989). "Higher-order attribute grammars." -- dynamic node synthesis for rollout rules
- Sloane, Kats, Visser (2010). "A pure OO embedding of attribute grammars." -- circular attributes, parameterized attributes
- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." -- scope hierarchy, shadowing
