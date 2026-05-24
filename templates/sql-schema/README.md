# Infrastructure Schema Demo

A scope-engine template demonstrating the full gen ecosystem via a SQL-like infrastructure schema DSL.

## Architecture

| Layer | Library | Role |
|---|---|---|
| Type definitions | gen-schema | 21 kinds with parent topology, cross-cutting refs, refinement contracts |
| Graph construction | scope-engine | Kinds as nodes, refs as import edges, `buildNodes` for indexed graph |
| Graph queries | gen-graph | FK-based join resolution, migration ordering, cycle detection, impact analysis |
| SQL engine | template-local | SQL string parser, query evaluator, WHERE/JOIN against live fleet data |
| DDL generator | template-local | Migration-ordered CREATE TABLE with FK constraints, indexes, views |
| ACL synthesis | template-local | LDAP identity x infrastructure topology x policy rules -> effective permissions |
| Network reachability | template-local | Firewall rules x network topology -> server-to-server connectivity |

## Data Model

21 schema kinds modeling multi-datacenter infrastructure:

- **Infrastructure:** datacenter, network, subnet, vlan
- **Compute:** server, interface
- **Services:** service, port, service-dependency
- **DNS:** domain, dns-record
- **Load balancing:** loadbalancer, backend
- **Security:** firewall-rule, certificate
- **Scheduling:** schedule
- **Identity:** ldap-group, ldap-role, user
- **Policy:** access-policy

Plus 2 synthesized kinds (effective-access, network-reachability) materialized at eval time.

## SQL Query Examples

```nix
# Simple SELECT with WHERE
query fleet "SELECT hostname, os FROM servers WHERE datacenter = 'us-east-1'"
# -> [ { hostname = "web-1"; os = "nixos"; } { hostname = "web-2"; ... } { hostname = "db-1"; ... } ]

# JOIN via FK
query fleet ''
  SELECT s.hostname, svc.name
  FROM servers s
  JOIN services svc ON svc.server = s.name
  WHERE s.datacenter = 'us-east-1'
''

# Multi-hop JOIN chain
query fleet ''
  SELECT s.hostname, svc.name, p.number
  FROM servers s
  JOIN services svc ON svc.server = s.name
  JOIN ports p ON p.service = svc.name
  WHERE p.expose = true
''

# NULL checks, ORDER BY, LIMIT
query fleet "SELECT hostname FROM servers WHERE replaces IS NOT NULL ORDER BY hostname LIMIT 5"
```

## DDL Generation

Produces migration-ordered CREATE TABLE statements:

```nix
ddl = generateDDL schema;
ddl.tables   # [ "CREATE TABLE datacenter ..." "CREATE TABLE environment ..." ... ]
ddl.indexes  # [ "CREATE INDEX idx_server_datacenter ON server(datacenter);" ... ]
ddl.views    # [ "CREATE VIEW user_permissions AS ..." ... ]
ddl.order    # [ "datacenter" "environment" "ldap-group" ... ] (topological sort)
```

## ACL Synthesis

Cross-model bridge: LDAP identity x infrastructure topology x policy -> permissions.

```nix
effectiveAccess = synthesizeAccess fleet;
# { "alice:server:web-1" = { actions = ["sudo" "restart" "ssh"]; via = "access-policy:ops-server-sudo"; }; ... }

# Who has sudo?
lib.filterAttrs (_: ea: builtins.elem "sudo" ea.actions) effectiveAccess
```

## Network Reachability

Firewall rules x topology -> server connectivity.

```nix
reachability = synthesizeReachability fleet;
# { "web-1:db-1" = { allowedPorts = [5432]; path = ["web-1" "db-1"]; }; ... }
```

## Running Tests

```bash
nix eval --override-input scope-engine . ./templates/sql-schema#tests
```

## File Structure

```
templates/sql-schema/
  flake.nix           # inputs: scope-engine, gen-schema, gen-graph, gen, nixpkgs
  lib/
    default.nix       # public API
    schema.nix        # 21 gen-schema kinds, refinements, validators
    fleet.nix         # demo fleet data (multi-datacenter infrastructure)
    sql.nix           # SQL string parser (tokenizer + recursive descent)
    engine.nix        # SQL query evaluator (JOIN, WHERE, ORDER BY, LIMIT)
    ddl.nix           # DDL generation (tables, indexes, views)
    acl.nix           # ACL synthesis (access-policy x graph -> effective-access)
    reachability.nix  # Network reachability (firewall x topology -> connectivity)
  tests.nix           # 107 tests across 9 suites
  README.md
```

## Test Suites

| Suite | Tests | Covers |
|---|---|---|
| smoke | 2 | Fleet loads, basic structure |
| schema | 12 | Kind count, parent topology, ref fields |
| fleet-eval | 24 | Ref resolution, self-refs, setOf, nullable refs |
| refinement | 7 | CIDR, env tier, VLAN ID, MAC, TCP port validation |
| graph | 8 | Kind/instance graphs, cycles, reachability, dependents |
| sql-parser | 15 | Tokenizer, SELECT/FROM/JOIN/WHERE, aliases, IN/IS NULL |
| sql-engine | 11 | Simple/filtered select, JOINs, ORDER BY, LIMIT, NULL checks |
| ddl | 10 | Tables, migration order, junction tables, indexes, views |
| acl | 8 | Direct/transitive scope, effective access, "who has sudo" |
| reachability | 4 | Firewall intersection, self-subnet, deny rules |
| integration | 5 | Full pipeline, cross-model queries |
