# Dependency Resolver

Package dependency resolution with version constraints, transitive dependencies, conflict detection, and custom edge labels for devDependencies.

## What it demonstrates

Packages form a dependency graph via import edges. HOAG synthesis computes resolved dependency manifests. Custom D edges separate devDependencies from runtime deps. Version conflicts are detected by collecting all packages with the same name.

```
workspace
├── app@1.0         → lib-http@2.3, lib-json@1.5
├── lib-http@2.3    → lib-json@1.5, lib-tls@1.2
├── lib-json@1.5
├── lib-json@2.0    ← version conflict
├── lib-tls@1.2
└── lib-logging@3.1 → lib-json@1.5     (devDependency of app)
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| `collectImports` | Neron 2015 §2.4 | Transitive API collection across dependency chain |
| HOAG synthesis | Vogt 1989 | Synthesize resolved manifest node with computed deps |
| Custom edge labels (D) | van Antwerpen 2018 §2.1 | devDependency separation from runtime imports |
| `collect` (global) | -- | Version conflict detection across all nodes |
| `evalDebug` | spec OQ #2 | Cycle-safe evaluation with structured traces |
| Synthesized attributes | Knuth 1968 | depDepth, depCount, allDeps roll up bottom-up |
| `siblings` | -- | Detect that lib-json@1.5 and lib-json@2.0 are siblings |
| `nodesByType` | -- | Query all libs, find synthesized manifest |

## Tests

20 tests covering: direct/transitive dependency resolution, available API collection, dep depth/count computation, devDependency separation, HOAG manifest synthesis, version conflict detection, typed queries, structural queries, and evalDebug compatibility.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- Mokhov, Mitchell, Peyton Jones (2018). "Build systems a la carte." ICFP 2018 -- demand-driven dependency evaluation
- Vogt, Swierstra, Kuiper (1989). "Higher-order attribute grammars." -- manifest synthesis
- van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018). "Scopes as types." -- custom edge labels
