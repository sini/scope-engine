# Config cascade tests.
{
  genScope,
  lib,
  result,
}:
{
  test-db-host = result.get "api.test" "config" "DB_HOST";
  test-log-level = result.get "api.test" "config" "LOG_LEVEL";
  test-port = result.get "api.test" "config" "PORT";
  staging-db = result.get "api.staging" "config" "DB_HOST";
  staging-port = result.get "api.staging" "config" "PORT";
  web-port = result.get "web" "config" "PORT";
  web-log-level = result.get "web" "config" "LOG_LEVEL";
  global-db-host = result.get "global" "config" "DB_HOST";

  api-cache-ttl = result.get "api" "config" "CACHE_TTL";
  api-redis = result.get "api" "config" "REDIS_HOST";
  test-cache-ttl = result.get "api.test" "config" "CACHE_TTL";
  infra-no-cache = result.get "infra" "config" "CACHE_TTL";

  api-test-full-config =
    let
      c = result.get "api.test" "resolvedConfig";
    in
    {
      DB_HOST = c.DB_HOST;
      LOG_LEVEL = c.LOG_LEVEL;
      PORT = c.PORT;
      has-cache = c ? CACHE_TTL;
    };
  web-full-config =
    let
      c = result.get "web" "resolvedConfig";
    in
    {
      PORT = c.PORT;
      LOG_LEVEL = c.LOG_LEVEL;
      DB_HOST = c.DB_HOST;
    };

  test-overridden = builtins.sort builtins.lessThan (result.get "api.test" "overriddenKeys");
  global-no-overrides = result.get "global" "overriddenKeys";

  test-config-sources =
    let
      s = result.get "api.test" "configSources";
    in
    {
      db = s.DB_HOST;
      log = s.LOG_LEVEL;
      port = s.PORT;
      cache = s.CACHE_TTL;
    };

  api-environments = builtins.sort builtins.lessThan (genScope.childrenIds result "api");
  api-test-ancestors = genScope.ancestors result "api.test";
  all-env-overrides = builtins.sort builtins.lessThan (
    builtins.attrNames (genScope.nodesByType result "env")
  );
}
