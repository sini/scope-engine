# Infrastructure Schema Demo

A scope-engine template demonstrating the full gen ecosystem via a SQL-like infrastructure schema DSL. 21 gen-schema kinds model a multi-datacenter fleet. A SQL query engine evaluates SELECT/JOIN/WHERE queries against live data. A DDL generator produces migration-ordered CREATE TABLE statements. Two cross-model synthesis engines materialize ACL permissions and network reachability.

This is the SQL equivalent of the [nest-traits](../nest-traits/) template's CSS selector engine. Nest uses CSS selectors to query a DOM and deliver configuration; this demo uses SQL queries to query an infrastructure graph and return result sets.

## Architecture

| Layer | Library | What it does here |
|---|---|---|
| **Type definitions** | [gen-schema](https://github.com/sini/gen-schema) | 21 kinds with parent topology, cross-cutting refs, refinement contracts |
| **Graph construction** | [scope-engine](https://github.com/sini/scope-engine) | Kind/instance nodes, FK import edges, `buildNodes` for indexed graph |
| **Graph queries** | [gen-graph](https://github.com/sini/gen-graph) | Migration ordering, cycle detection, impact analysis, dependency chains |
| **SQL engine** | template-local | SQL string parser, query evaluator, WHERE/JOIN against live fleet data |
| **DDL generator** | template-local | Migration-ordered CREATE TABLE with FKs, CHECKs, indexes, views |
| **ACL synthesis** | template-local | LDAP identity x infrastructure topology x policy → effective permissions |
| **Network reachability** | template-local | Firewall rules x network topology → server-to-server connectivity |
| **NixOS generator** | template-local | Infrastructure queries → NixOS module configs per server |
| **Rule engine** | template-local | SQL WHERE → NixOS module delivery (parallel to nest-traits CSS rules) |

## Quick Start

```bash
# Run all 148 tests
nix eval --override-input scope-engine ../.. .#tests

# Explore interactively
nix repl --override-input scope-engine ../.. .
# nix-repl> :l .#sql
# nix-repl> sql.query sql.rawFleet "SELECT hostname FROM servers WHERE datacenter = 'us-east-1'"
```

## Showcase

Everything below is evaluated from a single Nix expression. 21 schema kinds, 52 fleet instances, validated, graphed, queried, compiled to NixOS configs, and queryable end-to-end.

### Query raw infrastructure with SQL

```nix
# What servers are in us-east-1?
query fleet "SELECT hostname, cores, ram_gb FROM servers WHERE datacenter = 'us-east-1'"
# → [ { hostname = "web-1"; cores = 4; ram_gb = 8; }
#     { hostname = "web-2"; cores = 4; ram_gb = 8; }
#     { hostname = "db-1";  cores = 8; ram_gb = 32; } ]

# Multi-hop JOIN: what ports are exposed on which servers?
query fleet ''
  SELECT s.hostname, svc.name, p.number
  FROM servers s
  JOIN services svc ON svc.server = s.name
  JOIN ports p ON p.service = svc.name
  WHERE p.expose = true
''
# → [ { hostname = "web-1"; name = "nginx"; number = 80; }
#     { hostname = "web-1"; name = "nginx"; number = 443; }
#     { hostname = "api-1"; name = "api";   number = 50051; } ]

# Comparison operators: high-spec servers
query fleet "SELECT hostname, cores, ram_gb FROM servers WHERE cores > 4 AND ram_gb >= 16"
# → [ { hostname = "db-1"; cores = 8; ram_gb = 32; }
#     { hostname = "api-1"; cores = 4; ram_gb = 16; } ]

# LIKE with wildcards: servers matching a name pattern
query fleet "SELECT hostname FROM servers WHERE hostname LIKE 'web%'"
# → [ { hostname = "web-1"; } { hostname = "web-2"; } ]

# Privileged ports
query fleet "SELECT number, protocol FROM ports WHERE number < 1024"
# → [ { number = 80; protocol = "tcp"; } { number = 443; protocol = "tcp"; } ]

# Cross-domain: who has sudo access?
query fleet ''
  SELECT u.name, u.shell, r.permissions
  FROM users u
  JOIN ldap_roles r ON u.ldap_role = r.name
  WHERE 'sudo' IN r.permissions
''
# → [ { name = "alice"; shell = "/bin/zsh"; permissions = ["sudo" "deploy" "restart"]; } ]

# NULL checks: servers that are replacements
query fleet "SELECT hostname FROM servers WHERE replaces IS NOT NULL"
# → [ { hostname = "web-2"; } ]
```

### Validate with refinement contracts

```nix
# CIDR format, VLAN IDs (1-4094), MAC addresses, TCP ports (1-65535),
# environment tiers (dev/staging/prod), service protocols (tcp/udp/http/grpc),
# DNS record types (A/AAAA/CNAME/MX/TXT), LB algorithms, firewall actions.
# Invalid values throw at evaluation time with field path and message.

# Row-polymorphic validators cross-check fields:
#   server RAM must be >= 2x cores
#   DNS records must reference a server OR loadbalancer
#   certificates must be bound to a server OR loadbalancer
#   service-dependencies cannot be self-referential
```

### Analyze the dependency graph

```nix
# What are the root kinds? (create these first in migrations)
kindRoots
# → [ "datacenter" "environment" "ldap-group" ]

# What depends on the database server?
dependents "server:db-1"
# → [ "interface:db-1.eth0" "service:postgres" "schedule:db-backup" ... ]

# Any circular foreign key dependencies?
kindCycles
# → [ "loadbalancer" "server" "user" ]  (self-referential FKs)
```

### Generate migration-ordered DDL

```nix
ddl.order
# → [ "datacenter" "environment" "ldap_group" "network" "ldap_role" "subnet"
#     "vlan" "server" "domain" "loadbalancer" "interface" "service" ... ]

ddl.tables  # 21 CREATE TABLE statements with FKs, CHECKs, array columns
ddl.indexes # FK indexes: idx_server_datacenter, idx_service_server, ...
ddl.views   # CREATE VIEW user_permissions, server_network_map, ...
```

### Synthesize cross-model relationships

```nix
# ACL: LDAP identity × infrastructure × policy → effective permissions
effectiveAccess
# → { "alice:server:web-1" = { actions = ["sudo" "restart" "ssh"]; via = "ops-server-sudo"; };
#     "bob:service:api"    = { actions = ["deploy" "logs" "rollback"]; via = "eng-service-deploy"; }; }

# Network reachability: firewall rules × topology → server connectivity
networkReachability
# → { "web-1:db-1" = { allowedPorts = [5432]; }; }
```

### Build NixOS configurations from rules

```nix
# Rules: SQL WHERE clauses → NixOS modules (parallels nest-traits' CSS → config)
#   "all servers"          → openssh
#   "tags IN ('web')"      → nginx
#   "tags IN ('database')" → postgresql
#   "exposed port 443"     → ACME certs
#   "admin-role users"     → sudo
#   "environment = prod"   → prometheus monitoring

hostConfigs.web-1.services.nginx.enable       # → true
hostConfigs.web-1.security.acme.acceptTerms   # → true
hostConfigs.db-1.services.postgresql.enable    # → true
hostConfigs.db-1.services.nginx.enable         # → false
hostConfigs.api-1.security.sudo.enable         # → false  (bob is developer)
hostConfigs.web-1.security.sudo.enable         # → true   (alice is admin)
```

### Query the built NixOS configs with SQL

```nix
# The rendered configs are queryable too — SQL against the BUILT system, not just input data

queryHostConfigs "SELECT name FROM hosts WHERE nginx_enabled = true"
# → [ { name = "web-1"; } { name = "web-2"; } ]

queryHostConfigs "SELECT name FROM hosts WHERE sudo_enabled = true AND postgresql_enabled = false"
# → [ { name = "web-1"; } ]

queryHostConfigs "SELECT hostname, nginx_enabled, sudo_enabled, user_count FROM hosts WHERE name = 'web-1'"
# → [ { hostname = "web-1"; nginx_enabled = true; sudo_enabled = true; user_count = 1; } ]

# Config-path queries: walk any NixOS option path with a predicate
nixosQueries.serversWhere hostConfigs
  [ "networking" "firewall" "allowedTCPPorts" ]
  (ports: builtins.elem 443 ports)
# → { web-1 = { ... }; }

nixosQueries.serversWhere hostConfigs
  [ "users" "users" ]
  (users: users ? alice)
# → { db-1 = { ... }; web-1 = { ... }; }
```

### The full pipeline

```
Fleet data (52 instances across 21 kinds)
  → gen-schema validates (refinements, validators)
  → scope-engine builds dependency graph
  → gen-graph detects cycles, computes migration order
  → SQL engine queries raw infrastructure
  → ACL synthesis bridges LDAP → infrastructure
  → Network reachability bridges firewall rules → server connectivity
  → Rules match servers via SQL WHERE → deliver NixOS modules
  → NixOS configs built per-server (users, firewall, services, cron)
  → SQL queries run against the built configs
```

---

## How to Build Your Own Schema

This section walks through each primitive used in the demo so you can replicate the pattern for your own domain.

### Step 1: Define Schema Kinds

Each kind is a gen-schema entry under `config.schema.*`. Options are NixOS module options. Sidecars (`parent`, `validators`) are gen-schema extensions.

```nix
{ lib, schemaLib }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref setOf mkFieldValidator;
in
{
  evalSchema = fleet:
    let
      eval = lib.evalModules {
        modules = [{
          # Declare the schema
          options.schema = mkSchemaOption {};

          # A simple root kind — no parent, no refs
          config.schema.datacenter = {
            options.region = lib.mkOption { type = lib.types.str; };
          };

          # A kind with a parent (creates P-edges in scope-engine)
          config.schema.network = {
            parent = "datacenter";  # topology: network is child of datacenter
            options.cidr = lib.mkOption { type = lib.types.str; };
            options.datacenter = lib.mkOption { type = ref "datacenter"; };  # FK ref
          };

          # A kind with cross-cutting refs (creates I-edges in scope-engine)
          config.schema.server = {
            options.hostname = lib.mkOption { type = lib.types.str; };
            options.datacenter = lib.mkOption { type = ref "datacenter"; };
            options.environment = lib.mkOption { type = ref "environment"; };
            options.subnet = lib.mkOption { type = ref "subnet"; };
          };

          # Instance registries — one per kind
          options.datacenters = mkInstanceRegistry config.schema "datacenter" {};
          options.networks = mkInstanceRegistry config.schema "network" {
            refs.datacenter = config.datacenters;  # FK binding: network.datacenter → datacenter registry
          };
          options.servers = mkInstanceRegistry config.schema "server" {
            refs.datacenter = config.datacenters;
            refs.environment = config.environments;
            refs.subnet = config.subnets;
          };

          # Fleet data (or import from a separate file)
          config.datacenters.us-east-1 = { region = "us-east"; };
          config.networks."us-east-1.primary" = { cidr = "10.0.0.0/16"; datacenter = "us-east-1"; };
        }];
      };
    in {
      schema = eval.config.schema;
      fleet = { datacenter = eval.config.datacenters; network = eval.config.networks; };
    };
}
```

**Key concepts:**
- `mkSchemaOption {}` declares the schema container
- `config.schema.<kind>` defines a kind with `options.*` for fields
- `parent = "kind"` creates parent-child topology (P-edges)
- `ref "kind"` creates a foreign key reference (I-edges)
- `mkInstanceRegistry schema "kind" { refs = { ... }; }` creates an instance registry with FK bindings

### Step 2: Add Refinement Contracts

Refinement contracts validate field values at the type level. Declare them as lists of `{ check, message }` attrsets:

```nix
# Define reusable refinements
refinements = {
  cidr = [{
    check = v: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+" v != null;
    message = "must be valid CIDR notation (e.g., 10.0.0.0/16)";
  }];
  tcpPort = [{
    check = v: v >= 1 && v <= 65535;
    message = "must be a valid TCP port (1-65535)";
  }];
};

# Apply to kind options via mkInstanceRegistry's refinements parameter
options.networks = mkInstanceRegistry config.schema "network" {
  refinements = {
    cidr = refinements.cidr;  # validates at applyPipeline time
  };
  refs.datacenter = config.datacenters;
};
```

Refinements validate during `applyPipeline` (strict by default). Invalid values throw with the field path and message.

### Step 3: Add Row-Polymorphic Validators

Validators that declare which fields they need. They're automatically skipped for kinds that lack those fields:

```nix
# Validator that only runs on kinds with both 'server' and 'loadbalancer' fields
dnsHasTarget = mkFieldValidator {
  name = "dns-record-has-target";
  fields = [ "server" "loadbalancer" ];
  check = r: r.server != null || r.loadbalancer != null;
  message = "DNS record must reference a server or loadbalancer";
};

# Attach to a kind via the validators sidecar
config.schema.dns-record = {
  parent = "domain";
  options.server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
  options.loadbalancer = lib.mkOption { type = lib.types.nullOr (ref "loadbalancer"); default = null; };
  validators = [ dnsHasTarget ];
};
```

### Step 4: Advanced Ref Patterns

**Self-refs** — a kind referencing itself (nullable to break the cycle):

```nix
config.schema.server = {
  options.replaces = lib.mkOption {
    type = lib.types.nullOr (ref "server");
    default = null;
  };
};
# Fleet: servers.web-2 = { replaces = "web-1"; ... };
```

**setOf refs** — a kind referencing multiple instances of another kind:

```nix
config.schema.user = {
  options.servers = lib.mkOption {
    type = setOf (ref "server");
    default = [];
  };
};
# Fleet: users.alice = { servers = [ "web-1" "db-1" ]; ... };
```

**Nullable dual refs** — two optional refs where at least one must be set (enforced by validator):

```nix
config.schema.certificate = {
  options.server = lib.mkOption { type = lib.types.nullOr (ref "server"); default = null; };
  options.loadbalancer = lib.mkOption { type = lib.types.nullOr (ref "loadbalancer"); default = null; };
  validators = [ certHasTarget ];  # at-least-one validator
};
```

### Step 5: Build the Dependency Graph

After evaluating the schema, build scope-engine and gen-graph structures:

```nix
let
  engine = scope-engine { inherit lib; };
  graphLib = gen-graph { inherit lib engine; };

  # Evaluate schema + fleet
  result = evalSchema rawFleet;

  # Kind-level graph (kinds as nodes, ref declarations as edges)
  kindGraphInputs = schemaLib.buildKindGraph result.schema;
  kindNodes = engine.buildNodes kindGraphInputs;

  # Instance-level graph (instances as nodes, resolved refs as edges)
  instanceGraphInputs = schemaLib.buildInstanceGraph result.schema result.fleet;
  instanceNodes = engine.buildNodes instanceGraphInputs;
in {
  # Migration ordering: create independent kinds first
  roots = graphLib.roots kindNodes;
  # → [ "datacenter" "environment" "ldap-group" ]

  # Cycle detection
  cycles = graphLib.cycles kindNodes;
  # → [ "loadbalancer" "server" "user" ] (self-ref FKs)

  # Impact analysis: what depends on this?
  dependents = graphLib.dependents instanceNodes "server:db-1";
  # → services, schedules, interfaces on db-1

  # Transitive reachability
  reachable = graphLib.reachableFrom instanceNodes "server:web-1";
  # → datacenter, environment, subnet it belongs to
}
```

### Step 6: Write SQL Queries

The SQL query engine parses SQL strings and evaluates them against raw fleet data:

```nix
# Simple SELECT with WHERE
query fleet "SELECT hostname, os FROM servers WHERE datacenter = 'us-east-1'"
# → [ { hostname = "web-1"; os = "nixos"; } ... ]

# JOIN via FK — services running on servers
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

# Cross-model: who has sudo?
query fleet ''
  SELECT u.name, r.permissions
  FROM users u
  JOIN ldap-roles r ON u.ldap-role = r.name
  WHERE 'sudo' IN r.permissions
''

# NULL checks
query fleet "SELECT hostname FROM servers WHERE replaces IS NOT NULL"

# ORDER BY + LIMIT
query fleet "SELECT hostname, cores FROM servers ORDER BY cores LIMIT 3"
```

**Supported SQL subset:**

| Feature | Example |
|---|---|
| `SELECT col, col` | `SELECT hostname, os` |
| `SELECT *` | `SELECT *` |
| `FROM kind [alias]` | `FROM servers s` |
| `JOIN kind ON fk = pk` | `JOIN services svc ON svc.server = s.name` |
| `LEFT JOIN` | `LEFT JOIN interfaces i ON i.server = s.name` |
| `WHERE col = 'val'` | `WHERE datacenter = 'us-east-1'` |
| `WHERE col != 'val'` | `WHERE os != 'windows'` |
| `WHERE 'val' IN col` | `WHERE 'sudo' IN permissions` |
| `WHERE col IS NULL` | `WHERE replaces IS NULL` |
| `WHERE col IS NOT NULL` | `WHERE failover IS NOT NULL` |
| `AND` / `OR` | `WHERE cores > 4 AND ram_gb >= 16` |
| `ORDER BY col` | `ORDER BY hostname` |
| `LIMIT n` | `LIMIT 5` |

**How JOINs work:** The engine resolves `JOIN services svc ON svc.server = s.name` by looking up each service's `server` field value in the `servers` registry. This is O(1) per row via attrset lookup — the FK ref field tells the engine which registry to look in.

### Step 7: Generate DDL

The DDL generator produces migration-ordered SQL:

```nix
ddl = generateDDL schema;

ddl.order    # [ "datacenter" "environment" "ldap-group" ... ] topological sort
ddl.tables   # [ "CREATE TABLE datacenter (...)" "CREATE TABLE environment (...)" ... ]
ddl.indexes  # [ "CREATE INDEX idx_server_datacenter ON server(datacenter);" ... ]
ddl.views    # [ "CREATE VIEW user_permissions AS ..." ... ]
```

**What it generates:**
- `CREATE TABLE` with column types, `NOT NULL`, `PRIMARY KEY`, `DEFAULT`, `REFERENCES`
- `CHECK` constraints from enum refinements (e.g., `CHECK (tier IN ('dev', 'staging', 'prod'))`)
- Junction tables for `setOf` refs (e.g., `user_server(user_, server)`)
- Self-referential FKs (e.g., `replaces text REFERENCES server(name)`)
- Array columns for list fields (e.g., `tags text[]`)
- Indexes on every FK column
- Views for synthesis outputs
- Reserved word escaping (`user` → `user_`, `primary` → `primary_`)

### Step 8: Cross-Model Synthesis

Synthesis bridges independent schema domains using gen-graph queries:

**ACL synthesis** — LDAP identity x infrastructure x policy → permissions:

```nix
effectiveAccess = synthesizeAccess fleet;
# {
#   "alice:server:web-1" = { actions = ["sudo" "restart" "ssh"]; via = "ops-server-sudo"; };
#   "alice:server:db-1" = { actions = ["sudo" "restart" "ssh"]; via = "ops-server-sudo"; };
#   "bob:service:api" = { actions = ["deploy" "logs" "rollback"]; via = "eng-service-deploy"; };
# }

# Reverse query: who has sudo on web-1?
lib.filterAttrs (_: ea: builtins.elem "sudo" ea.actions) effectiveAccess
```

**Network reachability** — firewall rules x topology → server connectivity:

```nix
reachability = synthesizeReachability fleet;
# { "web-1:db-1" = { allowedPorts = [5432]; }; ... }

# Can web-1 reach db-1 on port 5432?
reachability."web-1:db-1".allowedPorts  # → [5432]
```

### Step 9: Generate NixOS Configurations

The NixOS configuration generator queries the fleet for each server's related infrastructure (services, ports, users, firewall rules, schedules) and produces a NixOS module attrset per server. This is the SQL equivalent of nest-traits' `class.nixos` builder: nest uses CSS selectors to pick config into hosts, this uses infrastructure queries.

```nix
# Build a module for a single server
mod = buildServerModule rawFleet "web-1";
# → { networking.hostName = "web-1"; networking.firewall.allowedTCPPorts = [80 443]; ... }

# Evaluate all servers at once
configs = nixosConfigs;
configs.web-1.networking.hostName          # → "web-1"
configs.web-1.networking.firewall.allowedTCPPorts  # → [80 443]
configs.api-1.users.users.bob.uid          # → 1001
```

**What it queries per server:**

| Relationship | How it's found | What it produces |
|---|---|---|
| Services | `service.server == serverName` | Service enablement |
| Ports | Exposed ports on the server's services | `networking.firewall.allowedTCPPorts` |
| Interfaces | `interface.server == serverName` | `networking.interfaces` with IP config |
| Users | `serverName` in `user.servers` | `users.users` with UID, shell, SSH keys |
| LDAP roles | `user.ldap-role` → `ldap-role.permissions` | `extraGroups = ["wheel"]` for sudo users |
| Schedules | `schedule.server == serverName` | `services.cron.systemCronJobs` |

**Post-eval query helpers** inspect the built configurations:

```nix
# Which servers have port 443 open?
nixosQueries.serversWithPort configs 443
# → { web-1 = { ... }; }

# Which servers have sudo users?
nixosQueries.serversWithSudo configs
# → { web-1 = { ... }; db-1 = { ... }; }

# All open ports across the fleet
nixosQueries.allOpenPorts configs
# → { web-1 = [80 443]; web-2 = []; db-1 = []; api-1 = [50051]; }

# Servers in a specific environment
nixosQueries.serversInEnv configs "prod"
# → { web-1 = ...; web-2 = ...; db-1 = ...; api-1 = ...; }
```

**Generic config-path queries** — SELECT WHERE on any NixOS config property:

```nix
# "Show me all servers where the firewall has port 443 open"
nixosQueries.serversWhere configs
  [ "networking" "firewall" "allowedTCPPorts" ]
  (ports: builtins.elem 443 ports)
# → { web-1 = { ... }; }

# "Which servers have cron jobs?"
nixosQueries.serversWhere configs
  [ "services" "cron" "systemCronJobs" ]
  (jobs: jobs != [])
# → { db-1 = { ... }; web-1 = { ... }; }

# "Which servers have user alice?"
nixosQueries.serversWhere configs
  [ "users" "users" ]
  (users: users ? alice)
# → { db-1 = { ... }; web-1 = { ... }; }

# "Which servers have the 'database' tag?"
nixosQueries.serversWhere configs
  [ "environment" "etc" "server-tags" "text" ]
  (tags: lib.hasInfix "database" tags)
# → { db-1 = { ... }; }

# Extract specific values from matching configs
nixosQueries.selectFromConfigs configs
  (cfg: cfg.networking.hostName)
  (hostname: configs.${hostname}.networking.firewall.allowedTCPPorts != [])
# → { web-1 = "web-1"; api-1 = "api-1"; }
```

`serversWhere` takes a config path (list of attr names) and a predicate. It walks the path with `lib.attrByPath`, then applies the predicate. This lets you query any property in the evaluated NixOS configuration — firewall rules, users, services, environment variables, cron jobs, tags — without writing kind-specific query functions.

### Step 10: Rule-Based Host Configuration

Rules deliver NixOS modules to servers based on SQL WHERE conditions — the direct parallel to nest-traits' CSS selector → config delivery.

**Nest-traits:** `{ is = traits.host; nixos = { boot.loader.grub.enable = true; }; }`
**SQL demo:** `{ where = "tags IN ('web')"; nixos = { services.nginx.enable = true; }; }`

```nix
# Define rules
rules = [
  # No WHERE = matches all servers
  { nixos = { services.openssh.enable = true; }; }

  # SQL WHERE → NixOS modules
  { where = "tags IN ('web')";
    nixos = { services.nginx.enable = true; }; }

  { where = "tags IN ('database')";
    nixos = { services.postgresql.enable = true; }; }

  # Complex: multi-join SQL identifies servers with exposed HTTPS
  { where = "SELECT s.name FROM servers s JOIN services svc ON svc.server = s.name JOIN ports p ON p.service = svc.name WHERE p.expose = true AND p.number = 443";
    nixos = { security.acme.acceptTerms = true; }; }

  # Dynamic: rule function receives fleet context
  { where = "tags IN ('web')";
    nixos = { fleet, server, ... }: {
      services.nginx.virtualHosts.${server.hostname} = {
        locations."/".proxyPass = "http://localhost:8080";
      };
    }; }

  # Match function: for queries the SQL engine can't express (e.g., setOf traversal)
  { match = { fleet, serverName, ... }:
      let
        adminUsers = lib.filterAttrs (_: u:
          (u.ldap-role or "") == "admin" && builtins.elem serverName (u.servers or [])
        ) (fleet.user or {});
      in adminUsers != {};
    nixos = { security.sudo.enable = true; }; }
];

# Build host configs: base (from fleet queries) + matching rules
hostConfigs = buildAllHostConfigs rawFleet rules buildServerModule;

# Query the results
hostConfigs.web-1.services.nginx.enable        # → true
hostConfigs.db-1.services.postgresql.enable     # → true
hostConfigs.web-1.security.acme.acceptTerms     # → true
hostConfigs.api-1.security.acme.acceptTerms     # → false (no port 443)
```

**Rule matching modes:**

| Mode | Field | Description |
|---|---|---|
| Match all | (none) | No `where` or `match` → applies to every server |
| SQL WHERE | `where` | WHERE clause wrapped as `SELECT name FROM servers WHERE ...` |
| Full SQL | `where` | SELECT query starting with `SELECT` — run as-is, check if server name in results |
| Nix predicate | `match` | Function `{ fleet, serverName, server } → bool` for queries beyond SQL's reach |

**NixOS delivery:** `nixos` can be a plain attrset (static) or a function `{ fleet, serverName, server } → attrset` (dynamic). The engine deep-merges the base module (from `buildServerModule`) with all matching rule modules in declaration order via `lib.recursiveUpdate`.

---

## Data Model

21 schema kinds modeling multi-datacenter infrastructure:

| Kind | Parent | Refs | Notable Features |
|---|---|---|---|
| `datacenter` | — | — | Root kind |
| `environment` | — | — | Refined: dev/staging/prod |
| `network` | datacenter | datacenter | CIDR refinement |
| `subnet` | network | network | CIDR + IPv4 gateway |
| `vlan` | subnet | subnet | VLAN ID refinement (1-4094) |
| `server` | — | datacenter, environment, subnet | Self-ref (`replaces`), tags (list), RAM validator |
| `interface` | server | server, vlan | MAC + IPv4 refinement |
| `service` | — | server, environment | Protocol refinement |
| `port` | service | service | TCP port refinement |
| `service-dependency` | — | service (dual) | No-self-dependency validator |
| `domain` | — | environment | |
| `dns-record` | domain | domain, server?, loadbalancer? | At-least-one-target validator |
| `loadbalancer` | — | datacenter, environment | Self-ref (`failover`), algorithm refinement |
| `backend` | loadbalancer | loadbalancer, service | |
| `firewall-rule` | — | subnet (dual), server? (dual) | Dual refs to same kind, priority |
| `certificate` | — | server?, loadbalancer? | At-least-one-target validator, domains list |
| `schedule` | — | service, server | Dual refs |
| `ldap-group` | — | — | Root kind |
| `ldap-role` | — | ldap-group | Permissions list |
| `user` | — | ldap-role | Self-ref (`manager`), setOf servers |
| `access-policy` | — | ldap-role | Scope: direct/transitive |

Plus 2 synthesized outputs: `effective-access`, `network-reachability`.

## Comparison with Nest CSS

| Nest CSS Template | SQL Schema Template |
|---|---|
| CSS selectors query DOM nodes | SQL queries query infrastructure resources |
| `parseCssSel` string parser | `parseSql` string parser |
| `matchesOne` evaluates selector | `evalWhere` evaluates predicate |
| `:has(trait)` child selector | `JOIN ... ON fk = pk` |
| `:within(trait)` ancestor selector | Multi-hop JOIN chains |
| `[attr=val]` attribute selector | `WHERE col = 'val'` |
| Rule delivers `{ nixos = config; }` | Rule delivers `{ where = "..."; nixos = config; }` |
| Traits with `needs`/`neededBy` | Kinds with `ref`/`parent` |
| CSS specificity | Migration ordering (topological sort) |

## File Structure

```
templates/sql-schema/
  flake.nix           # inputs: scope-engine, gen-schema, gen-graph, gen, nixpkgs
  lib/
    default.nix       # public API: evalSchema, query, generateDDL, synthesis
    schema.nix        # 21 gen-schema kinds, refinements, validators
    fleet.nix         # demo fleet data (52 instances across 21 kinds)
    sql.nix           # SQL tokenizer + recursive descent parser
    engine.nix        # SQL query evaluator (JOIN, WHERE, ORDER BY, LIMIT)
    ddl.nix           # DDL generation (tables, indexes, views)
    acl.nix           # ACL synthesis
    reachability.nix  # network reachability synthesis
    nixos.nix         # NixOS configuration generator
    rules.nix         # Rule engine: SQL WHERE → NixOS module delivery
  tests.nix           # 134 tests across 13 suites
  README.md
```

## Test Suites

| Suite | Tests | Covers |
|---|---|---|
| smoke | 2 | Fleet loads, basic structure |
| schema | 12 | Kind count, parent topology, ref fields |
| fleet-eval | 24 | Ref resolution, self-refs, setOf, nullable refs |
| refinement | 7 | CIDR, env tier, VLAN ID, MAC, TCP port validation |
| graph | 9 | Kind/instance graphs, cycles, reachability, dependents |
| sql-parser | 15 | Tokenizer, SELECT/FROM/JOIN/WHERE, aliases, IN/IS NULL |
| sql-engine | 11 | Simple/filtered select, JOINs, ORDER BY, LIMIT |
| ddl | 10 | Tables, migration order, junction tables, indexes, views |
| acl | 8 | Direct/transitive scope, effective access, "who has sudo" |
| reachability | 4 | Firewall intersection, self-subnet, deny rules |
| nixos | 16 | Config generation, user provisioning, post-eval queries |
| rules | 11 | Rule matching, SQL WHERE, match functions, base merge |
| integration | 5 | Full pipeline, cross-model queries |

## Running Tests

```bash
cd scope-engine/templates/sql-schema
nix eval --override-input scope-engine ../.. .#tests
```

## References

- [gen-schema](https://github.com/sini/gen-schema) — typed record registries with refinement contracts and mixins
- [gen-graph](https://github.com/sini/gen-graph) — monotonic query combinators over scope graphs
- [scope-engine](https://github.com/sini/scope-engine) — demand-driven attribute grammar evaluator
- [gen](https://github.com/sini/gen) — record algebra, search monad, intensional functions
- [nest-traits](../nest-traits/) — the CSS selector equivalent of this SQL demo
