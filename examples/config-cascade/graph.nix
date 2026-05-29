# Config cascade scope graph.
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
{ genScope }:
{
  roots = genScope.buildNodes {
    parentGraph = genScope.overlays [
      (genScope.star "global" [
        "apps"
        "shared"
        "infra"
      ])
      (genScope.star "apps" [
        "api"
        "web"
      ])
      (genScope.star "api" [
        "api.staging"
        "api.test"
      ])
    ];
    importGraph = genScope.overlays [
      (genScope.edge "api" "shared")
    ];
    decls = {
      global = {
        LOG_LEVEL = "warn";
        PORT = 8080;
        DB_HOST = "db.prod";
      };
      apps = {
        LOG_LEVEL = "info";
      };
      api = {
        PORT = 3000;
      };
      "api.staging" = {
        DB_HOST = "db.staging";
      };
      "api.test" = {
        DB_HOST = "localhost";
        LOG_LEVEL = "debug";
      };
      web = {
        PORT = 4000;
      };
      shared = {
        CACHE_TTL = 300;
        REDIS_HOST = "redis.internal";
      };
      infra = {
        REGION = "us-east-1";
      };
    };
    types = {
      global = "root";
      apps = "dir";
      api = "dir";
      "api.staging" = "env";
      "api.test" = "env";
      web = "dir";
      shared = "dir";
      infra = "dir";
    };
  };
}
