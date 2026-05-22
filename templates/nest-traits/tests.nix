{
  lib,
  engine,
  nest,
  schemaLib,
  aspects,
  genLib,
}:
{
  smoke = {
    test-nest-evaluates = {
      expr = nest ? evalNest;
      expected = true;
    };
    test-selectors-exist = {
      expr = nest ? selectors;
      expected = true;
    };
  };

  dom =
    let
      hostTrait = {
        __traitName = "host";
      };
      userTrait = {
        __traitName = "user";
      };
      inherit (nest) walkDom buildDomGraph;
    in
    {
      test-single-node = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                system = "x86_64-linux";
              };
            };
          in
          builtins.length nodes;
        expected = 1;
      };

      test-node-attrs = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                system = "x86_64-linux";
              };
            };
            n = builtins.head nodes;
          in
          {
            inherit (n)
              name
              __path
              __parentPath
              system
              ;
          };
        expected = {
          name = "igloo";
          __path = "igloo";
          __parentPath = null;
          system = "x86_64-linux";
        };
      };

      test-namespace-inheritance = {
        expr =
          let
            nodes = walkDom { } {
              prod = {
                env = "production";
                web-1 = {
                  is = [ hostTrait ];
                };
              };
            };
            n = builtins.head nodes;
          in
          n.env;
        expected = "production";
      };

      test-node-overrides-inherited = {
        expr =
          let
            nodes = walkDom { } {
              prod = {
                env = "production";
                web-1 = {
                  is = [ hostTrait ];
                  env = "staging";
                };
              };
            };
            n = builtins.head nodes;
          in
          n.env;
        expected = "staging";
      };

      test-nested-nodes = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                users.tux = {
                  is = [ userTrait ];
                };
              };
            };
          in
          builtins.length nodes;
        expected = 2;
      };

      test-nested-parent-path = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                users.tux = {
                  is = [ userTrait ];
                };
              };
            };
            tux = builtins.elemAt nodes 1;
          in
          tux.__parentPath;
        expected = "igloo";
      };

      test-multiple-namespace-levels = {
        expr =
          let
            nodes = walkDom { } {
              dc1 = {
                region = "us-east";
                prod = {
                  env = "prod";
                  web-1 = {
                    is = [ hostTrait ];
                  };
                };
              };
            };
            n = builtins.head nodes;
          in
          {
            inherit (n) region env;
          };
        expected = {
          region = "us-east";
          env = "prod";
        };
      };

      test-graph-has-parent-edges = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                users.tux = {
                  is = [ userTrait ];
                };
              };
            };
            graph = buildDomGraph nodes;
          in
          graph ? "igloo" && graph ? "igloo.users.tux" && graph."igloo.users.tux".parent == "igloo";
        expected = true;
      };

      test-graph-children = {
        expr =
          let
            nodes = walkDom { } {
              igloo = {
                is = [ hostTrait ];
                users.tux = {
                  is = [ userTrait ];
                };
              };
            };
            graph = buildDomGraph nodes;
          in
          graph."igloo".childrenIds;
        expected = [ "igloo.users.tux" ];
      };
    };

  css =
    let
      inherit (nest.css) parseCompound parseCssSel;
    in
    {
      test-star = {
        expr = parseCssSel "*";
        expected = {
          __sel = "star";
        };
      };
      test-id = {
        expr = parseCssSel "#web-1";
        expected = {
          __sel = "id";
          name = "web-1";
        };
      };
      test-class = {
        expr = parseCssSel ".nixos";
        expected = {
          __sel = "class";
          name = "nixos";
        };
      };
      test-attr-eq = {
        expr = parseCssSel "[env=prod]";
        expected = {
          __sel = "attr";
          key = "env";
          val = "prod";
        };
      };
      test-attr-exists = {
        expr = parseCssSel "[system]";
        expected = {
          __sel = "attrExists";
          key = "system";
        };
      };
      test-name = {
        expr = parseCssSel "server";
        expected = {
          __sel = "name";
          name = "server";
        };
      };
      test-compound-and = {
        expr = parseCssSel "#web-1[env=prod]";
        expected = [
          {
            __sel = "id";
            name = "web-1";
          }
          {
            __sel = "attr";
            key = "env";
            val = "prod";
          }
        ];
      };
      test-or = {
        expr = parseCssSel "server,web";
        expected = {
          __sel = "or";
          selectors = [
            {
              __sel = "name";
              name = "server";
            }
            {
              __sel = "name";
              name = "web";
            }
          ];
        };
      };
      test-child-combinator = {
        expr = parseCssSel "prod > web";
        expected = {
          __sel = "child";
          parentSel = {
            __sel = "name";
            name = "prod";
          };
          childSel = {
            __sel = "name";
            name = "web";
          };
        };
      };
      test-descendant-combinator = {
        expr = parseCssSel "prod + web";
        expected = {
          __sel = "descendant";
          ancestorSel = {
            __sel = "name";
            name = "prod";
          };
          descendantSel = {
            __sel = "name";
            name = "web";
          };
        };
      };
      test-pseudo-not = {
        expr = parseCssSel ":not(server)";
        expected = {
          __sel = "not";
          selector = {
            __sel = "name";
            name = "server";
          };
        };
      };
      test-pseudo-has = {
        expr = parseCssSel ":has(admin)";
        expected = {
          __sel = "has";
          selector = {
            __sel = "name";
            name = "admin";
          };
        };
      };
    };
}
