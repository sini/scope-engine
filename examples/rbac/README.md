# RBAC Permission Resolver

Role-based access control with role hierarchies, multi-role assignment, resource permission inheritance, and deny overrides.

## What it demonstrates

Roles form a hierarchy via R (role inheritance) edges. Users are assigned roles via A (assignment) edges. Resources form a tree via parent edges with inherited properties. Deny overrides use D (deny) edges and scoped relations. Resolution determines effective permissions through the role hierarchy.

```
Role hierarchy:           Users:                Resources:
  viewer (read)             alice → admin         org/
  ├── editor (write)        bob → editor+auditor  ├── project-x/ (high)
  │   └── admin (delete,    carol → viewer        │   ├── doc-1
  │         manage)         dave → editor          │   └── doc-2
  └── auditor (audit)         + DENIED on proj-x  └── project-y/ (low)
                                                      └── doc-3
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| Custom edge labels (R, A, D) | van Antwerpen 2018 §2.1 | Role inheritance, user assignment, deny edges |
| `followEdge` | van Antwerpen 2018 §2.1 | Traverse role hierarchy and user assignments |
| `paramAttr` | Sloane 2010 §3 | hasPermission, isDenied, canAccess parameterized checks |
| `inherit'` | Neron 2015 §2.3 | Resource sensitivity inherited from parent resources |
| Scoped relations | van Antwerpen 2018 §2.1 | Deny rules as named relations on user nodes |
| `nodesByType` | -- | Query all users, roles, resources independently |
| `ancestors` / `childrenIds` | -- | Resource tree structure for documents |

## Tests

25 tests covering: role hierarchy resolution (viewer/editor/admin/auditor permission chains), user effective permissions (multi-role union), permission checks (positive/negative), deny overrides (blocked actions on specific resources), resource hierarchy (inherited sensitivity), structural queries, and typed queries.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018). "Scopes as types." -- custom edge labels, scoped relations
- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." -- class inheritance as import (§3), inherited attributes
- Sloane, Kats, Visser (2010). "A pure OO embedding of attribute grammars." -- parameterized attributes
