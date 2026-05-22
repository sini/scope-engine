# Config Cascade Resolver

Hierarchical configuration override system modeling .env files at directory levels, Kubernetes kustomize overlays, or Terraform variable inheritance.

## What it demonstrates

Parent edges encode directory/namespace nesting (deeper overrides shallower). Import edges encode explicit source/include directives. Resolution walks the scope chain: the deepest value wins. Config source tracing identifies where each key originates.

```
/                            LOG_LEVEL=warn, PORT=8080, DB_HOST=db.prod
├── apps/                    LOG_LEVEL=info
│   ├── api/                 PORT=3000; imports shared/
│   │   ├── .env.staging     DB_HOST=db.staging
│   │   └── .env.test        DB_HOST=localhost, LOG_LEVEL=debug
│   └── web/                 PORT=4000
├── shared/                  CACHE_TTL=300, REDIS_HOST=redis.internal
└── infra/                   REGION=us-east-1
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| `inherit'` | Neron 2015 §2.3 | Config values inherited down the directory tree |
| `shadow` | Neron 2015 §5 Def. 1 | Deeper config values override shallower ones |
| `query` with `labelWF` | Neron 2015 §2.4 | Import-based includes (shared config) |
| `queryAll` | Neron 2015 §2.3 | Override detection: find keys set at multiple levels |
| `paramAttr` | Sloane 2010 §3 | Parameterized config key lookup |
| `collectImports` | Neron 2015 §2.4 | Gather config from included scopes |
| `ancestors` | -- | Trace the full config inheritance chain |
| `nodesByType` | -- | Find all environment override files |

## Tests

20 tests covering: deep-overrides-shallow resolution, import-based includes (api gets shared CACHE_TTL), full config merging across levels, override detection (which keys are overridden), config source tracing (local/import/inherited), structural queries (environments, ancestors), and typed queries.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." -- scope hierarchy, shadowing, import edges
- Sloane, Kats, Visser (2010). "A pure OO embedding of attribute grammars." -- parameterized attributes
