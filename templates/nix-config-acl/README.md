# nix-config ACL

Unified access control with three-level scope graph resolution, replicating the full ACL topology from [nix-config/docs/ACL.md](https://github.com/sini/nix-config).

## What it demonstrates

Groups are the single primitive for access control. They can contain users and other groups (transitive membership). Access is environment-scoped. Host login is gate-controlled via system-access-groups at both environment and host levels, merged at resolution time.

```
groups                                ← shared definitions (kanidm, unix, system scopes)
  |
environments.<env>.access             ← user → [group] bindings per environment
  |
env.system-access-groups              ← env-wide baseline login gates
  + host.system-access-groups         ← host-specific login gates (merged with env)
  |
resolved user                         ← enable + systemGroups derived from above
```

### Topology

```
Groups:
  admins (kanidm) ──M──→ users (kanidm)
  users ──M──→ grafana.access, media.access
  system-access (system) ──M──→ workstation-access, server-access
  wheel, podman, audio, video, render, libvirtd (unix)

Environments:
  prod ──P──→ cortex, blade, patch, axon-01
  dev  ──P──→ dev-box

Users:
  sini  = admins + system-access + wheel + podman + libvirtd + audio + video + render
  shuo  = users + workstation-access + wheel + podman + audio + video + render
  json  = admins                          ← identity-only, no system-access
  greco = users                           ← no login, kanidm groups only
```

## Resolution examples

### sini on cortex

```
direct groups     = [ admins system-access wheel podman libvirtd audio video render ]
transitive        = + [ users grafana.access media.access workstation-access server-access ... ]
cortex gates      = [ system-access workstation-access ]
system ∩ gates    = [ system-access ] → enable = true
unix groups       = [ wheel podman libvirtd audio video render ]
```

### json on cortex

```
direct groups     = [ admins ]
transitive        = + [ users grafana.access media.access ... ]
system-scoped     = [] → no system groups
cortex gates      = [ system-access workstation-access ]
system ∩ gates    = [] → enable = false (identity-only, no Unix account)
```

### shuo on axon-01

```
direct groups     = [ users workstation-access wheel ... ]
axon gates        = [ system-access server-access ]
system ∩ gates    = [] → enable = false
(workstation-access does NOT reverse-grant system-access)
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| Custom edge labels (M) | van Antwerpen 2018 §2.1 | Group membership as labeled edges |
| `followEdge` | van Antwerpen 2018 §2.1 | Traverse membership chains for transitive resolution |
| `paramAttr` | Sloane 2010 §3 | Per-user resolution on a per-host basis |
| `shadow` | Neron 2015 §5 | Merging effective gate lists |
| `collect` with scope filter | -- | Partition groups by scope (kanidm/unix/system) |
| `nodesByType` | -- | Query all users, hosts, environments, groups |
| Parent edges | Neron 2015 §2.3 | Host-environment-root hierarchy |
| `ancestors` / `childrenIds` | -- | Host ancestry, environment children |
| `inherit_` | Neron 2015 §2.3 | Gate resolution from environment to host |

## Tests

25 tests validating the exact resolution examples from the ACL spec:

- **sini on cortex**: enable=true, full unix groups, system-access confirmed
- **json on cortex**: enable=false, identity-only, no unix/system groups
- **shuo on cortex**: enable=true, workstation-access gate match
- **shuo on axon-01**: enable=false, workstation-access not in server gates
- **greco on cortex**: enable=false, kanidm groups only
- **hugs on cortex**: enable=false, has grafana.server-admins
- **sini on dev-box**: enable=true, reduced unix groups (dev env)
- Transitive membership chains (admins → users → grafana.access)
- Effective gate merging (env + host system-access-groups)
- Group scope filtering (kanidm/unix/system partitioning)
- Group graph structure (M edge traversal)
- Host ancestry and environment children

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018). "Scopes as types." -- custom edge labels, scoped relations
- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." -- scope hierarchy, resolution calculus
- Sloane, Kats, Visser (2010). "A pure OO embedding of attribute grammars." -- parameterized attributes
