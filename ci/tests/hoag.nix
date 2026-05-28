{ lib, engine, ... }:
let
  # Multi-level: env → host → user
  roots = engine.buildNodes {
    parentGraph = engine.overlays [
      (engine.edge "host1" "env")
      (engine.edge "user1" "host1")
      (engine.edge "user2" "host1")
    ];
    importGraph = engine.empty;
    decls = {
      env = {
        name = "production";
      };
      host1 = {
        hostname = "srv1";
      };
      user1 = {
        username = "alice";
      };
      user2 = {
        username = "bob";
      };
    };
    types = {
      env = "env";
      host1 = "host";
      user1 = "user";
      user2 = "user";
    };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: [ ];
      label =
        self: id:
        let
          node = self.node id;
        in
        node.decls.hostname or node.decls.username or node.decls.name or id;
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };

  # Derived children: proxy nodes synthesized conditionally
  proxyRoots = engine.buildNodes {
    parentGraph = engine.edge "svc" "cluster";
    importGraph = engine.empty;
    decls = {
      cluster = {
        proxy = true;
      };
      svc = {
        port = 8080;
      };
    };
    types = {
      cluster = "cluster";
      svc = "service";
    };
  };

  proxyResult = engine.eval {
    roots = proxyRoots;
    attributes = {
      children = self: id: lib.filterAttrs (_: n: n.parent == id) proxyRoots;
      imports = self: id: [ ];
      derived-children =
        self: id:
        let
          node = self.node id;
        in
        if node.decls.proxy or false then
          {
            "${id}-proxy" = {
              id = "${id}-proxy";
              type = "proxy";
              parent = id;
              decls = {
                upstream = id;
              };
            };
          }
        else
          { };
      port = self: id: (self.node id).decls.port or null;
    };
    parseParent =
      id:
      if proxyRoots ? ${id} then
        proxyRoots.${id}.parent
      else
        # Derived children: parse parent from id suffix
        let
          parts = lib.splitString "-proxy" id;
        in
        if builtins.length parts > 1 then builtins.head parts else null;
  };
in
{
  flake.tests."hoag" = {
    test-multi-level-env-label = {
      expr = result.get "env" "label";
      expected = "production";
    };

    test-multi-level-host-label = {
      expr = result.get "host1" "label";
      expected = "srv1";
    };

    test-multi-level-user-label = {
      expr = result.get "user1" "label";
      expected = "alice";
    };

    test-multi-level-children-env = {
      expr = builtins.attrNames (result.get "env" "children");
      expected = [ "host1" ];
    };

    test-multi-level-children-host = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames (result.get "host1" "children"));
      expected = [
        "user1"
        "user2"
      ];
    };

    test-multi-level-parent-chain = {
      expr = (result.node "user1").parent;
      expected = "host1";
    };

    test-multi-level-grandparent = {
      expr = (result.node "host1").parent;
      expected = "env";
    };

    test-derived-children-proxy-exists = {
      expr = builtins.attrNames (proxyResult.get "cluster" "derived-children");
      expected = [ "cluster-proxy" ];
    };

    test-derived-children-non-proxy = {
      expr = proxyResult.get "svc" "derived-children";
      expected = { };
    };

    test-derived-child-reachable = {
      expr = (proxyResult.node "cluster-proxy").type;
      expected = "proxy";
    };

    test-derived-child-decls = {
      expr = (proxyResult.node "cluster-proxy").decls.upstream;
      expected = "cluster";
    };

    test-allNodes-includes-derived = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames proxyResult.allNodes);
      expected = [
        "cluster"
        "cluster-proxy"
        "svc"
      ];
    };
  };
}
