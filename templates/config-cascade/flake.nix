{
  description = "Config cascade resolver: hierarchical config override (.env/kustomize pattern)";

  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };

      # ═══════════════════════════════════════════════════════════════
      # Hierarchical config cascade
      #
      # Models config inheritance like .env files at directory levels,
      # Kubernetes kustomize overlays, or Terraform variable inheritance.
      #
      # Parent edges = directory/namespace nesting (deeper overrides).
      # Import edges = explicit source/include directives.
      # Declarations = config values at each level.
      # Resolution = deepest value wins (D < I < P).
      #
      # Directory structure:
      #   /                              (global defaults)
      #   ├── .env                       LOG_LEVEL=warn, PORT=8080, DB_HOST=db.prod
      #   ├── apps/
      #   │   ├── .env                   LOG_LEVEL=info (overrides global)
      #   │   ├── api/
      #   │   │   ├── .env              PORT=3000 (overrides global)
      #   │   │   ├── .env.staging      DB_HOST=db.staging
      #   │   │   └── .env.test         DB_HOST=localhost, LOG_LEVEL=debug
      #   │   └── web/
      #   │       └── .env              PORT=4000
      #   ├── shared/
      #   │   └── .env                  CACHE_TTL=300, REDIS_HOST=redis.internal
      #   └── infra/
      #       └── .env                  REGION=us-east-1
      #
      # Include: api imports shared (for CACHE_TTL, REDIS_HOST)
      # Include: api.staging includes api base
      # ═══════════════════════════════════════════════════════════════

      baseNodes = engine.buildNodes {
        # Directory nesting
        parentGraph = engine.overlays [
          (engine.star "global" [ "apps" "shared" "infra" ])
          (engine.star "apps" [ "api" "web" ])
          (engine.star "api" [ "api.staging" "api.test" ])
        ];
        # Explicit includes
        importGraph = engine.overlays [
          # api includes shared config
          (engine.edge "api" "shared")
          # staging inherits from api base (already has via parent, but also
          # could have overlay-specific includes)
        ];
        decls = {
          global = { LOG_LEVEL = "warn"; PORT = 8080; DB_HOST = "db.prod"; };
          apps = { LOG_LEVEL = "info"; };
          api = { PORT = 3000; };
          "api.staging" = { DB_HOST = "db.staging"; };
          "api.test" = { DB_HOST = "localhost"; LOG_LEVEL = "debug"; };
          web = { PORT = 4000; };
          shared = { CACHE_TTL = 300; REDIS_HOST = "redis.internal"; };
          infra = { REGION = "us-east-1"; };
        };
        types = {
          global = "root";
          apps = "dir"; api = "dir"; "api.staging" = "env"; "api.test" = "env";
          web = "dir"; shared = "dir"; infra = "dir";
        };
      };

      attributes = {
        # Resolve a config key: walks the scope chain (deepest wins).
        config = engine.paramAttr (self: id: key:
          engine.query {
            dataFilter = node: node.decls.${key} or null;
          } self id);

        # Full resolved config: merge all levels with inner-shadows-outer.
        resolvedConfig = self: id:
          let
            node = self.nodes.${id};
            local = node.decls;
            importedConfigs = lib.foldl' (acc: iid:
              engine.shadow (self.evaluated.${iid}.get "resolvedConfig") acc
            ) {} node.imports;
            parentConfig =
              if node.parent != null
              then self.evaluated.${node.parent}.get "resolvedConfig"
              else {};
          in engine.shadow local (engine.shadow importedConfigs parentConfig);

        # Detect config conflicts: keys set at multiple levels
        overriddenKeys = self: id:
          let
            allResults = key: engine.queryAll {
              dataFilter = node: node.decls.${key} or null;
            } self id;
            localKeys = builtins.attrNames self.nodes.${id}.decls;
          in builtins.filter (key:
            builtins.length (allResults key) > 1
          ) localKeys;

        # Config source tracing: where does each key come from?
        configSources = self: id:
          let
            resolved = self.evaluated.${id}.get "resolvedConfig";
          in lib.mapAttrs (key: _value:
            let
              node = self.nodes.${id};
              isLocal = node.decls ? ${key};
              isImported = builtins.any (iid:
                (self.evaluated.${iid}.get "resolvedConfig") ? ${key}
              ) node.imports;
            in if isLocal then "local"
               else if isImported then "import"
               else "inherited"
          ) resolved;
      };

      result = engine.eval { inherit baseNodes attributes; };

    in
    {
      # ─── Config resolution: deep overrides shallow ──────────────────

      # api.test: DB_HOST=localhost (local override)
      tests.test-db-host =
        result.evaluated."api.test".get "config" "DB_HOST";
        # → "localhost"

      # api.test: LOG_LEVEL=debug (local override)
      tests.test-log-level =
        result.evaluated."api.test".get "config" "LOG_LEVEL";
        # → "debug"

      # api.test: PORT not set locally → walks to api (3000)
      tests.test-port =
        result.evaluated."api.test".get "config" "PORT";
        # → 3000

      # api.staging: DB_HOST=db.staging (local), PORT from api (3000)
      tests.staging-db =
        result.evaluated."api.staging".get "config" "DB_HOST";
        # → "db.staging"

      tests.staging-port =
        result.evaluated."api.staging".get "config" "PORT";
        # → 3000

      # web: PORT=4000 (local), LOG_LEVEL=info (from apps parent)
      tests.web-port =
        result.evaluated.web.get "config" "PORT";
        # → 4000

      tests.web-log-level =
        result.evaluated.web.get "config" "LOG_LEVEL";
        # → "info"

      # Global defaults: everything defined at root
      tests.global-db-host =
        result.evaluated.global.get "config" "DB_HOST";
        # → "db.prod"

      # ─── Import-based includes ──────────────────────────────────────

      # api imports shared: gets CACHE_TTL and REDIS_HOST
      tests.api-cache-ttl =
        result.evaluated.api.get "config" "CACHE_TTL";
        # → 300

      tests.api-redis =
        result.evaluated.api.get "config" "REDIS_HOST";
        # → "redis.internal"

      # api.test inherits api's imports transitively via parent
      tests.test-cache-ttl =
        result.evaluated."api.test".get "config" "CACHE_TTL";
        # → 300

      # infra doesn't import shared: no CACHE_TTL
      tests.infra-no-cache =
        result.evaluated.infra.get "config" "CACHE_TTL";
        # → null

      # ─── Full resolved config ───────────────────────────────────────

      tests.api-test-full-config =
        let c = result.evaluated."api.test".get "resolvedConfig";
        in {
          DB_HOST = c.DB_HOST;
          LOG_LEVEL = c.LOG_LEVEL;
          PORT = c.PORT;
          has-cache = c ? CACHE_TTL;
        };
        # → { DB_HOST = "localhost"; LOG_LEVEL = "debug"; PORT = 3000; has-cache = true; }

      tests.web-full-config =
        let c = result.evaluated.web.get "resolvedConfig";
        in {
          PORT = c.PORT;
          LOG_LEVEL = c.LOG_LEVEL;
          DB_HOST = c.DB_HOST;
        };
        # → { PORT = 4000; LOG_LEVEL = "info"; DB_HOST = "db.prod"; }

      # ─── Override detection ─────────────────────────────────────────

      # api.test overrides DB_HOST and LOG_LEVEL (set locally AND higher up)
      tests.test-overridden =
        builtins.sort builtins.lessThan
          (result.evaluated."api.test".get "overriddenKeys");
        # → [ "DB_HOST" "LOG_LEVEL" ]

      # global has no overrides (it's the root)
      tests.global-no-overrides =
        result.evaluated.global.get "overriddenKeys";
        # → []

      # ─── Config source tracing ──────────────────────────────────────

      tests.test-config-sources =
        let s = result.evaluated."api.test".get "configSources";
        in {
          db = s.DB_HOST;        # local (overridden)
          log = s.LOG_LEVEL;     # local (overridden)
          port = s.PORT;         # inherited (from api parent)
          cache = s.CACHE_TTL;   # inherited (api.test → api → shared import, but from test's POV it's inherited)
        };

      # ─── Structural queries ─────────────────────────────────────────

      tests.api-environments =
        builtins.sort builtins.lessThan (engine.childrenIds result "api");
        # → [ "api.staging" "api.test" ]

      tests.api-test-ancestors =
        engine.ancestors result "api.test";
        # → [ "api" "apps" "global" ]

      tests.all-env-overrides =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "env"));
        # → [ "api.staging" "api.test" ]
    };
}
