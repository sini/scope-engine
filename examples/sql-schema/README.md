# Infrastructure Schema Demo

Flagship integration demo for the [gen ecosystem](https://github.com/sini/gen): all 8 libraries composing to model, validate, query, derive, bind, and graph a multi-datacenter infrastructure fleet. A SQL engine queries live data. A rule engine dispatches NixOS configuration via stratified fixpoint. A DDL generator produces migration-ordered SQL. Cross-model synthesis computes ACL permissions and network reachability.

This is the SQL counterpart of the [nest-traits](../nest-traits/) CSS selector demo. Where nest uses CSS selectors to query a DOM, this demo uses SQL queries to query an infrastructure graph.

## Libraries

| Library | Role in this demo |
|---|---|
| [gen-algebra](https://github.com/sini/gen-algebra) | Identity hashing, validators, ref types for schema internals |
| [gen-schema](https://github.com/sini/gen-schema) | 21 kinds with parent topology, FK refs, refinement contracts, row-polymorphic validators |
| [gen-scope](https://github.com/sini/gen-scope) | `buildNodes` for kind-level and instance-level graph construction |
| [gen-graph](https://github.com/sini/gen-graph) | Reachability, cycle detection, migration ordering, impact analysis, ACL transitive walks |
| [gen-select](https://github.com/sini/gen-select) | WHERE clause compilation: SQL AST nodes become compositional selectors (`and`, `when`, `star`) |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch: `mkRule` with selector conditions, phased actions, fixpoint convergence |
| [gen-bind](https://github.com/sini/gen-bind) | NixOS module wrapping with contracts, provenance, and signature introspection |
| nixpkgs `lib` | `evalModules` for schema evaluation, general utilities |

## Architecture

```
Fleet data (52 instances across 21 kinds)
  |
  v
gen-schema: evalModules validates refs, refinements, row validators
  |
  +--> gen-scope: buildNodes (kind graph + instance graph)
  |       |
  |       +--> gen-graph: roots, cycles, reachableFrom, dependents, impactOf
  |
  +--> SQL parser (recursive descent) --> SQL engine
  |       |
  |       +--> gen-select: astToSelector compiles WHERE AST to selectors
  |       |       `sel.and`, `sel.when`, `sel.star` compose predicates
  |       |       `sel.matches` evaluates against row context
  |       |
  |       +--> gen-derive: mkRule + fixpoint dispatch
  |               condition = gen-select selector
  |               produce = phased action list (enrich | nixos)
  |               fixpoint: enrich actions feed back into context
  |
  +--> gen-bind: wrap server module with contracts + provenance
  |       bindings = { fleet, serverName, server }
  |       contracts = { server = hasFields [...] }
  |
  +--> DDL generator: schema introspection --> CREATE TABLE / INDEX / VIEW
  |
  +--> ACL synthesis: user --> ldap-role --> access-policy --> gen-graph walk
  |
  +--> Network reachability: firewall rules x subnet topology --> connectivity
```

## Schema

21 gen-schema kinds model a multi-datacenter infrastructure:

| Kind | Parent | Key refs | Notes |
|---|---|---|---|
| `datacenter` | -- | -- | Root kind |
| `environment` | -- | -- | Refined: dev/staging/prod |
| `network` | datacenter | datacenter | CIDR refinement |
| `subnet` | network | network | CIDR + IPv4 gateway |
| `vlan` | subnet | subnet | VLAN ID refinement (1-4094) |
| `server` | -- | datacenter, environment, subnet | Self-ref (`replaces`), tags, RAM validator |
| `interface` | server | server, vlan | MAC + IPv4 refinement |
| `service` | -- | server, environment | Protocol refinement |
| `port` | service | service | TCP port refinement (1-65535) |
| `service-dependency` | -- | upstream service, downstream service | No-self-dependency validator |
| `domain` | -- | environment | |
| `dns-record` | domain | domain, server?, loadbalancer? | At-least-one-target validator |
| `loadbalancer` | -- | datacenter, environment | Self-ref (`failover`), LB algorithm refinement |
| `backend` | loadbalancer | loadbalancer, service | |
| `firewall-rule` | -- | src-subnet, dst-subnet, src-server?, dst-server? | Dual refs to same kind |
| `certificate` | -- | server?, loadbalancer? | At-least-one-target validator |
| `schedule` | -- | service, server | |
| `ldap-group` | -- | -- | Root kind |
| `ldap-role` | -- | ldap-group | Permissions list |
| `user` | -- | ldap-role | Self-ref (`manager`), `setOf` servers |
| `access-policy` | -- | ldap-role | Scope: direct/transitive |

Refinement contracts validate: CIDR, IPv4, MAC, VLAN ID (1-4094), TCP port (1-65535), env tier, service protocol, DNS record type, LB algorithm, firewall action, cert issuer.

Row-polymorphic validators: `server-ram-proportional` (RAM >= 2x cores), `dns-record-has-target`, `cert-has-target`, `no-self-dependency`. These auto-skip kinds that lack the required fields.

## Fleet Data

52 instances across the 21 kinds, modeling a two-datacenter (us-east-1, eu-west-1) production infrastructure with 4 servers (web-1, web-2, db-1, api-1), 3 services (nginx, postgres, api), 2 users (alice/admin, bob/developer), load balancers, DNS, firewall rules, certificates, and LDAP identity.

## SQL Engine

Two-stage: parser + evaluator.

**Parser** (`sql.nix`): tokenizer + recursive descent. Produces AST: `{ select, from, joins, where, orderBy, limit }`.

**Evaluator** (`engine.nix`): resolves JOINs via FK field lookup in instance registries (O(1) per row), compiles WHERE to gen-select selectors, projects columns, sorts, limits.

### gen-select WHERE Bridge

The key cross-library integration. `astToSelector` compiles each WHERE AST node into a gen-select selector:

```nix
# SQL: WHERE datacenter = 'us-east-1' AND cores > 4
# Becomes:
sel.and [
  (sel.when (_id: ctx: (ctx.data _id).datacenter == "us-east-1"))
  (sel.when (_id: ctx: (ctx.data _id).cores > 4))
]
```

Each row is wrapped in a gen-select five-field accessor context (`mkRowContext`), then `sel.matches` evaluates the selector. Supported operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `LIKE`, `IN`, `IS NULL`, `IS NOT NULL`, `AND`, `OR`.

```nix
sql.query "SELECT hostname, cores FROM servers WHERE cores > 4 AND ram_gb >= 16"
# --> [ { hostname = "db-1"; cores = 8; } { hostname = "api-1"; cores = 4; } ]
```

## Rule Dispatch

Rules use gen-derive's `mkRule` with gen-select selectors as conditions. Two action phases:

| Phase | Actions | Purpose |
|---|---|---|
| `structural` | `enrich` | Feed data back into context (fixpoint converges) |
| `config` | `nixos` | Collect NixOS module fragments |

```nix
# Web servers get nginx
deriveLib.mkRule {
  condition = sel.when (_id: ctx: builtins.elem "web" ((ctx.data _id).tags or []));
  produce = _id: _ctx: [ (fx.nixos { services.nginx.enable = true; }) ];
  identity = "web-nginx";
}
```

### Fixpoint Convergence

Pass 1 enriches web servers with `has-nginx = true`. Pass 2 fires only on enriched context, adding nginx monitoring. gen-derive's `fixpoint` iterates until no new rules fire.

```nix
# Pass 1: enrichment
{ condition = sel.when (...web tagged...);
  produce = _: _: [ (fx.enrich { key = "has-nginx"; value = true; }) ]; }

# Pass 2: fires after enrichment
{ condition = sel.when (_id: ctx: (ctx.data _id).has-nginx or false);
  produce = _: _: [ (fx.nixos { services.prometheus.exporters.nginx.enable = true; }) ]; }
```

## NixOS Config Generation

`nixos.nix` uses gen-bind to wrap server modules with contracts and provenance:

```nix
bindLib.wrap {
  module = serverModuleFn;
  bindings = { inherit fleet serverName server; };
  contracts = {
    server = bindLib.contract.hasFields [ "hostname" "os" "cores" "datacenter" "environment" ];
  };
  provenance = {
    server = { source = "fleet-registry"; scope = "server=${serverName}"; };
  };
}
```

The wrapped result exposes `{ module, wrapped, signature, advertisedArgs }`. `signature.bound` shows which args were injected. Contract violations throw at bind time, not at NixOS eval time.

Per-server config queries infrastructure relationships (services, ports, interfaces, users, firewall rules, schedules) and produces a NixOS module attrset. The base module + gen-derive rule output are deep-merged via `lib.recursiveUpdate`.

## Graph Queries

gen-graph runs on two graph levels:

**Kind-level graph** -- schema kinds as nodes, ref declarations as edges:

```nix
graphLib.roots kindNodes       # --> [ "datacenter" "environment" "ldap-group" ]
graphLib.cycles kindNodes      # --> [ "loadbalancer" "server" "user" ] (self-refs)
```

**Instance-level graph** -- 52 instances as nodes, resolved refs as edges:

```nix
graphLib.reachableFrom instanceNodes "server:web-1"
# --> [ "datacenter:us-east-1" "environment:prod" "subnet:us-east-1.primary.web" ... ]

graphLib.dependents instanceNodes "datacenter:us-east-1"
# --> [ "server:web-1" "network:us-east-1.primary" ... ]
```

## ACL Synthesis

Cross-model bridge: user --> ldap-role --> access-policy --> resource targets.

Two scopes:

- **direct**: user's assigned servers (or services on them, or LBs fronting those)
- **transitive**: gen-graph `reachableFrom` on a bidirectional instance graph (`graphLib.transpose` + forward edges)

```nix
effectiveAccess."alice:server:web-1".actions  # --> [ "sudo" "restart" "ssh" ]
effectiveAccess."bob:service:api".actions      # --> [ "deploy" "logs" "rollback" ]
```

## DDL Generation

Reads schema metadata, produces migration-ordered SQL via Kahn's algorithm (topological sort):

```nix
ddl.order    # [ "datacenter" "environment" "ldap-group" ... ]
ddl.tables   # 21+ CREATE TABLE statements (includes junction tables for setOf refs)
ddl.indexes  # FK indexes: idx_server_datacenter, idx_service_server, ...
ddl.views    # user_permissions, server_network_map
```

Generates: column types, NOT NULL, PRIMARY KEY, REFERENCES, CHECK constraints from enum refinements, junction tables for `setOf` refs (e.g., `user_server`), self-referential FKs, array columns, reserved word escaping (`user` --> `user_`, `primary` --> `primary_`).

## Cross-Library Bridges

Three bridge demos showing multi-library pipelines:

**gen-select --> gen-graph**: selector filters instance graph nodes

```nix
prodSelector = sel.when (_id: ctx: (ctx.data _id).type == "server");
matching = builtins.filter (id: sel.matches prodSelector id ctx) serverNodes;
```

**gen-select --> gen-derive**: selector condition dispatches rule, produces actions

```nix
testRule = deriveLib.mkRule {
  condition = sel.when (_id: ctx: builtins.elem "web" ((ctx.data _id).tags or []));
  produce = _id: _ctx: [{ __action = "tagged"; value = true; }];
  identity = "bridge-test";
};
```

**gen-schema --> gen-graph**: schema introspection feeds kind-level graph for reachability

```nix
graphLib.reachableFrom kindNodes "server"
# --> [ "datacenter" "environment" "network" "subnet" ]
```

## Test Suites

17 suites, 170 tests:

| Suite | Tests | Covers |
|---|---|---|
| `smoke` | 2 | Fleet loads, basic structure |
| `schema` | 12 | Kind count, parent topology, ref fields |
| `fleet-eval` | 24 | Ref resolution, self-refs, setOf, nullable refs |
| `refinement` | 7 | CIDR, env tier, VLAN ID, MAC, TCP port validation |
| `graph` | 9 | Kind/instance graphs, cycles, reachability, dependents |
| `sql-parser` | 15 | Tokenizer, SELECT/FROM/JOIN/WHERE, aliases, IN/IS NULL |
| `sql-engine` | 11 | Simple/filtered select, JOINs, ORDER BY, LIMIT |
| `ddl` | 10 | Tables, migration order, junction tables, indexes, views |
| `acl` | 8 | Direct/transitive scope, effective access |
| `reachability` | 4 | Firewall intersection, self-subnet, deny rules |
| `bind` | 5 | gen-bind wrapping, signatures, contracts |
| `nixos` | 22 | Config generation, user provisioning, config-path queries |
| `config-queries` | 18 | SQL against rendered NixOS configs |
| `rules` | 11 | gen-derive dispatch, SQL WHERE conditions, base merge |
| `fixpoint` | 4 | Enrichment feedback, multi-pass convergence |
| `integration` | 5 | Full pipeline, cross-model queries |
| `bridge` | 3 | Cross-library: select-->graph, select-->derive, schema-->graph |

## Running

```bash
# Run all tests
nix eval .#tests

# Interactive REPL
nix repl .
# nix-repl> sql.query "SELECT hostname FROM servers WHERE datacenter = 'us-east-1'"
# nix-repl> sql.hostConfigs.web-1.services.nginx.enable
# nix-repl> sql.effectiveAccess
```

## File Structure

```
examples/sql-schema/
  flake.nix           # inputs: all 8 gen-* libraries + nixpkgs
  lib/
    default.nix       # orchestration: graph construction, demoRules, exports
    schema.nix        # 21 gen-schema kinds, refinements, validators
    fleet.nix         # demo fleet data (52 instances)
    sql.nix           # SQL tokenizer + recursive descent parser
    engine.nix        # SQL evaluator: JOINs, WHERE via gen-select, ORDER BY, LIMIT
    ddl.nix           # DDL generation: tables, indexes, views
    acl.nix           # ACL synthesis via gen-graph transitive walks
    reachability.nix  # network reachability synthesis
    nixos.nix         # NixOS config generator via gen-bind wrapping
    rules.nix         # gen-derive stratified dispatch with gen-select conditions
  tests.nix           # 170 tests across 17 suites
  README.md
```

## References

- [gen ecosystem](https://github.com/sini/gen) -- architecture, terminology, and library overview
- [gen-schema](https://github.com/sini/gen-schema) -- typed record registries with refinement contracts
- [gen-graph](https://github.com/sini/gen-graph) -- accessor-based graph query combinators
- [gen-scope](https://github.com/sini/gen-scope) -- demand-driven HOAG evaluator
- [gen-select](https://github.com/sini/gen-select) -- compositional selector algebra
- [gen-derive](https://github.com/sini/gen-derive) -- stratified rule dispatch with fixpoint convergence
- [gen-bind](https://github.com/sini/gen-bind) -- module binding with contracts and provenance
- [gen-algebra](https://github.com/sini/gen-algebra) -- search monad, intensional functions, record algebra
- [nest-traits](../nest-traits/) -- the CSS selector equivalent of this SQL demo
