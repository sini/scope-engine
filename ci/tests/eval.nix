{ lib, engine, ... }:
let
  # Minimal graph: two roots, a and b
  roots = engine.buildNodes {
    parentGraph = engine.edge "child" "parent";
    importGraph = engine.empty;
    decls = {
      parent = {
        x = 1;
        y = 2;
      };
      child = {
        x = 10;
      };
    };
    types = {
      parent = "host";
      child = "user";
    };
  };

  result = engine.eval {
    inherit roots;
    attributes = {
      children =
        self: id:
        let
          node = self.node id;
        in
        lib.filterAttrs (_: n: n.parent == id) roots;
      imports = self: id: [ ];
      greeting = self: id: "hello-${id}";
      declX = self: id: (self.node id).decls.x or 0;
    };
    parseParent =
      id:
      let
        node = roots.${id} or null;
      in
      if node != null then node.parent else null;
  };

  # Single root, no children
  singleRoots = engine.buildNodes {
    parentGraph = engine.vertex "solo";
    importGraph = engine.empty;
    decls = {
      solo = {
        val = 42;
      };
    };
    types = {
      solo = "host";
    };
  };

  singleResult = engine.eval {
    roots = singleRoots;
    attributes = {
      children = self: id: { };
      imports = self: id: [ ];
      value = self: id: (self.node id).decls.val or 0;
    };
  };
in
{
  "eval" = {
    test-node-returns-root = {
      expr = (result.node "parent").id;
      expected = "parent";
    };

    test-node-returns-child = {
      expr = (result.node "child").id;
      expected = "child";
    };

    test-node-type = {
      expr = (result.node "parent").type;
      expected = "host";
    };

    test-node-decls = {
      expr = (result.node "parent").decls.x;
      expected = 1;
    };

    test-get-custom-attr = {
      expr = result.get "parent" "greeting";
      expected = "hello-parent";
    };

    test-get-custom-attr-child = {
      expr = result.get "child" "greeting";
      expected = "hello-child";
    };

    test-get-declX-parent = {
      expr = result.get "parent" "declX";
      expected = 1;
    };

    test-get-declX-child = {
      expr = result.get "child" "declX";
      expected = 10;
    };

    test-children-of-parent = {
      expr = builtins.attrNames (result.get "parent" "children");
      expected = [ "child" ];
    };

    test-children-of-child = {
      expr = builtins.attrNames (result.get "child" "children");
      expected = [ ];
    };

    test-allNodes-keys = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames result.allNodes);
      expected = [
        "child"
        "parent"
      ];
    };

    test-single-root-value = {
      expr = singleResult.get "solo" "value";
      expected = 42;
    };

    test-single-root-allNodes = {
      expr = builtins.attrNames singleResult.allNodes;
      expected = [ "solo" ];
    };

    test-unknown-attr-throws = {
      expr = builtins.tryEval (result.get "parent" "nonexistent");
      expected = {
        success = false;
        value = false;
      };
    };

    test-unreachable-node-throws = {
      expr = builtins.tryEval (result.node "ghost");
      expected = {
        success = false;
        value = false;
      };
    };

    # --- Tier 2 selective materialization ---

    test-subtreeOf = {
      expr =
        let
          roots = {
            "env:prod" = {
              id = "env:prod";
              type = "env";
              parent = null;
              decls = {
                hosts = [ "web" ];
              };
            };
            "env:dev" = {
              id = "env:dev";
              type = "env";
              parent = null;
              decls = {
                hosts = [ "dev-1" ];
              };
            };
          };
          attributes = {
            children =
              self: id:
              let
                n = self.node id;
              in
              lib.listToAttrs (
                map (h: {
                  name = "host:${h}@${id}";
                  value = {
                    id = "host:${h}@${id}";
                    type = "host";
                    parent = id;
                    decls = { };
                  };
                }) (n.decls.hosts or [ ])
              );
          };
          parseParent =
            id:
            let
              parts = lib.splitString "@" id;
            in
            if builtins.length parts > 1 then lib.concatStringsSep "@" (lib.drop 1 parts) else null;
          result = engine.eval { inherit roots attributes parseParent; };
        in
        builtins.sort builtins.lessThan (builtins.attrNames (result.subtreeOf "env:prod"));
      expected = [
        "env:prod"
        "host:web@env:prod"
      ];
    };

    test-nodesOfType = {
      expr =
        let
          roots = {
            "env:prod" = {
              id = "env:prod";
              type = "env";
              parent = null;
              decls = {
                hosts = [
                  "web"
                  "db"
                ];
              };
            };
          };
          attributes = {
            children =
              self: id:
              let
                n = self.node id;
              in
              lib.listToAttrs (
                map (h: {
                  name = "host:${h}@${id}";
                  value = {
                    id = "host:${h}@${id}";
                    type = "host";
                    parent = id;
                    decls = { };
                  };
                }) (n.decls.hosts or [ ])
              );
          };
          parseParent =
            id:
            let
              parts = lib.splitString "@" id;
            in
            if builtins.length parts > 1 then lib.concatStringsSep "@" (lib.drop 1 parts) else null;
          result = engine.eval { inherit roots attributes parseParent; };
        in
        builtins.sort builtins.lessThan (builtins.attrNames (result.nodesOfType "host"));
      expected = [
        "host:db@env:prod"
        "host:web@env:prod"
      ];
    };

    test-allNodesWhere = {
      expr =
        let
          roots = {
            "env:prod" = {
              id = "env:prod";
              type = "env";
              parent = null;
              decls = {
                hosts = [ "web" ];
                secure = true;
              };
            };
            "env:dev" = {
              id = "env:dev";
              type = "env";
              parent = null;
              decls = {
                hosts = [ "dev-1" ];
                secure = false;
              };
            };
          };
          attributes = {
            children =
              self: id:
              let
                n = self.node id;
              in
              lib.listToAttrs (
                map (h: {
                  name = "host:${h}@${id}";
                  value = {
                    id = "host:${h}@${id}";
                    type = "host";
                    parent = id;
                    decls = {
                      secure = n.decls.secure or false;
                    };
                  };
                }) (n.decls.hosts or [ ])
              );
          };
          parseParent =
            id:
            let
              parts = lib.splitString "@" id;
            in
            if builtins.length parts > 1 then lib.concatStringsSep "@" (lib.drop 1 parts) else null;
          result = engine.eval { inherit roots attributes parseParent; };
        in
        builtins.sort builtins.lessThan (
          builtins.attrNames (result.allNodesWhere (n: n.decls.secure or false))
        );
      expected = [
        "env:prod"
        "host:web@env:prod"
      ];
    };
  };
}
