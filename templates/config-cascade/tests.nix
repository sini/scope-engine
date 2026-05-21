# Config cascade tests.
{ engine, lib, result }:
{
  test-db-host = result.evaluated."api.test".get "config" "DB_HOST";
  test-log-level = result.evaluated."api.test".get "config" "LOG_LEVEL";
  test-port = result.evaluated."api.test".get "config" "PORT";
  staging-db = result.evaluated."api.staging".get "config" "DB_HOST";
  staging-port = result.evaluated."api.staging".get "config" "PORT";
  web-port = result.evaluated.web.get "config" "PORT";
  web-log-level = result.evaluated.web.get "config" "LOG_LEVEL";
  global-db-host = result.evaluated.global.get "config" "DB_HOST";

  api-cache-ttl = result.evaluated.api.get "config" "CACHE_TTL";
  api-redis = result.evaluated.api.get "config" "REDIS_HOST";
  test-cache-ttl = result.evaluated."api.test".get "config" "CACHE_TTL";
  infra-no-cache = result.evaluated.infra.get "config" "CACHE_TTL";

  api-test-full-config = let c = result.evaluated."api.test".get "resolvedConfig"; in {
    DB_HOST = c.DB_HOST; LOG_LEVEL = c.LOG_LEVEL; PORT = c.PORT; has-cache = c ? CACHE_TTL;
  };
  web-full-config = let c = result.evaluated.web.get "resolvedConfig"; in {
    PORT = c.PORT; LOG_LEVEL = c.LOG_LEVEL; DB_HOST = c.DB_HOST;
  };

  test-overridden = builtins.sort builtins.lessThan (result.evaluated."api.test".get "overriddenKeys");
  global-no-overrides = result.evaluated.global.get "overriddenKeys";

  test-config-sources = let s = result.evaluated."api.test".get "configSources"; in {
    db = s.DB_HOST; log = s.LOG_LEVEL; port = s.PORT;
    cache = s.CACHE_TTL;
  };

  api-environments = builtins.sort builtins.lessThan (engine.childrenIds result "api");
  api-test-ancestors = engine.ancestors result "api.test";
  all-env-overrides = builtins.sort builtins.lessThan (builtins.attrNames (engine.nodesByType result "env"));
}
