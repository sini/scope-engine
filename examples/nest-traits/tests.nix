{
  lib,
  engine,
  nest,
  schemaLib,
  aspects,
  genLib,
  graphLib,
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
      hostT = {
        name = "host";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class.nixos = _: _: null;
      };
      userT = {
        name = "user";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      inherit (nest) walkDom buildDomGraph;
    in
    {
      test-single-node = {
        expr =
          let
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
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
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
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
            nodes = walkDom {
              prod = {
                env = "production";
                web-1 = {
                  is = [ hostT ];
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
            nodes = walkDom {
              prod = {
                env = "production";
                web-1 = {
                  is = [ hostT ];
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
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [ userT ];
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
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [ userT ];
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
            nodes = walkDom {
              dc1 = {
                region = "us-east";
                prod = {
                  env = "prod";
                  web-1 = {
                    is = [ hostT ];
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
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [ userT ];
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
            nodes = walkDom {
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [ userT ];
                };
              };
            };
            graph = buildDomGraph nodes;
            childIds = builtins.attrNames (lib.filterAttrs (_: n: n.parent == "igloo") graph);
          in
          childIds;
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

  selectors =
    let
      hostTrait = {
        name = "host";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class.nixos = _: _: null;
      };
      userTrait = {
        name = "user";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      serverTrait = {
        name = "server";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      nodes = [
        {
          name = "web-1";
          __path = "prod.web-1";
          __parentPath = "prod";
          is = [
            hostTrait
            serverTrait
          ];
          env = "prod";
          system = "x86_64-linux";
        }
        {
          name = "web-2";
          __path = "prod.web-2";
          __parentPath = "prod";
          is = [ hostTrait ];
          env = "prod";
        }
        {
          name = "alice";
          __path = "prod.web-1.alice";
          __parentPath = "prod.web-1";
          is = [ userTrait ];
        }
        {
          name = "prod";
          __path = "prod";
          __parentPath = null;
          is = [ ];
        }
      ];
      web1 = builtins.elemAt nodes 0;
      web2 = builtins.elemAt nodes 1;
      alice = builtins.elemAt nodes 2;
      ctx = name: nest.mkCtx name nodes;
      inherit (nest) matchesOne;
      sel = nest.selectors;
    in
    {
      test-trait-match = {
        expr = matchesOne web1 hostTrait (ctx web1);
        expected = true;
      };
      test-trait-no-match = {
        expr = matchesOne web1 userTrait (ctx web1);
        expected = false;
      };
      test-star = {
        expr = matchesOne web1 sel.star (ctx web1);
        expected = true;
      };
      test-and-compound = {
        expr = matchesOne web1 [ hostTrait serverTrait ] (ctx web1);
        expected = true;
      };
      test-and-compound-fail = {
        expr = matchesOne web2 [ hostTrait serverTrait ] (ctx web2);
        expected = false;
      };
      test-attr-eq = {
        expr = matchesOne web1 (sel.attrs { env = "prod"; }) (ctx web1);
        expected = true;
      };
      test-attr-eq-fail = {
        expr = matchesOne web1 (sel.attrs { env = "staging"; }) (ctx web1);
        expected = false;
      };
      test-not = {
        expr = matchesOne web1 (sel.not serverTrait) (ctx web1);
        expected = false;
      };
      test-not-pass = {
        expr = matchesOne web2 (sel.not serverTrait) (ctx web2);
        expected = true;
      };
      test-has-child = {
        expr = matchesOne web1 (sel.has userTrait) (ctx web1);
        expected = true;
      };
      test-has-child-fail = {
        expr = matchesOne web2 (sel.has userTrait) (ctx web2);
        expected = false;
      };
      test-within = {
        expr = matchesOne alice (sel.within hostTrait) (ctx alice);
        expected = true;
      };
      test-when = {
        expr = matchesOne web1 (sel.when ({ select, ... }: web1.env == "prod")) (ctx web1);
        expected = true;
      };
      test-class-match = {
        expr = matchesOne web1 (sel.class "nixos") (ctx web1);
        expected = true;
      };
      test-css-string = {
        expr = matchesOne web1 "#web-1" (ctx web1);
        expected = true;
      };
      test-css-attr = {
        expr = matchesOne web1 "[env=prod]" (ctx web1);
        expected = true;
      };
      test-call-with-args = {
        expr = nest.callWithArgs ({ select, host, ... }: host.name) web1 (ctx web1);
        expected = "web-1";
      };
    };

  traits =
    let
      traits = rec {
        host = {
          name = "host";
          class.nixos = _: _: null;
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
        };
        server = {
          name = "server";
          needs = [
            nginx
            firewall
          ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        nginx = {
          name = "nginx";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        firewall = {
          name = "firewall";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        monitoring = {
          name = "monitoring";
          neededBy = [ server ];
          needs = [ ];
          synth = [ ];
          class = { };
        };
        web = {
          name = "web";
          needs = [ server ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        circA = {
          name = "circA";
          needs = [ circB ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        circB = {
          name = "circB";
          needs = [ circA ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
      };

      inherit (nest) expandTraits expandNeededBy;
      traitNames = ts: map (t: t.name) ts;
    in
    {
      test-no-needs = {
        expr = traitNames (expandTraits [ traits.host ]);
        expected = [ "host" ];
      };
      test-direct-needs = {
        expr = builtins.sort builtins.lessThan (traitNames (expandTraits [ traits.server ]));
        expected = [
          "firewall"
          "nginx"
          "server"
        ];
      };
      test-transitive-needs = {
        expr = builtins.sort builtins.lessThan (traitNames (expandTraits [ traits.web ]));
        expected = [
          "firewall"
          "nginx"
          "server"
          "web"
        ];
      };
      test-diamond-dedup = {
        expr =
          let
            expanded = expandTraits [
              traits.web
              traits.server
            ];
            names = traitNames expanded;
          in
          builtins.length (builtins.filter (n: n == "server") names);
        expected = 1;
      };
      test-circular-needs-safe = {
        expr =
          let
            expanded = expandTraits [ traits.circA ];
          in
          builtins.sort builtins.lessThan (traitNames expanded);
        expected = [
          "circA"
          "circB"
        ];
      };
      test-neededby-injection = {
        expr =
          let
            expanded = expandNeededBy traits [
              traits.host
              traits.server
            ];
          in
          builtins.any (t: t.name == "monitoring") expanded;
        expected = true;
      };
      test-neededby-no-match = {
        expr =
          let
            expanded = expandNeededBy traits [ traits.host ];
          in
          builtins.any (t: t.name == "monitoring") expanded;
        expected = false;
      };
      test-needs-as-function = {
        expr =
          let
            dynT = {
              name = "dynamic";
              needs = [ traits.nginx ];
              neededBy = [ ];
              synth = [ ];
              class = { };
            };
            expanded = expandTraits [ dynT ];
          in
          builtins.sort builtins.lessThan (traitNames expanded);
        expected = [
          "dynamic"
          "nginx"
        ];
      };
    };

  engine-tests =
    let
      mockNixos = _select: modules: {
        _type = "nixos";
        modules = modules;
      };
      mockHm = _select: modules: {
        homeManager = modules;
      };
      traits = rec {
        host = {
          name = "host";
          class.nixos = mockNixos;
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
        };
        user = {
          name = "user";
          class.homeManager = mockHm;
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
        };
        server = {
          name = "server";
          needs = [ nginx ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        nginx = {
          name = "nginx";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        admin = {
          name = "admin";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        monitoring = {
          name = "monitoring";
          neededBy = [ server ];
          needs = [ ];
          synth = [ ];
          class = { };
        };
      };
      sel = nest.selectors;
    in
    {
      test-basic-output = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.host;
                  nixos = {
                    networking.hostName = "test";
                  };
                }
              ];
              igloo = {
                is = [ "host" ];
              };
            };
          in
          result ? outputs && result.outputs ? igloo;
        expected = true;
      };

      test-by-class = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.host;
                  nixos = {
                    networking.hostName = "test";
                  };
                }
              ];
              igloo = {
                is = [ "host" ];
              };
            };
          in
          result ? byClass && result.byClass ? nixos;
        expected = true;
      };

      test-rule-matching = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.server;
                  nixos = {
                    services.nginx.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  "host"
                  "server"
                ];
              };
              db-1 = {
                is = [ "host" ];
              };
            };
          in
          {
            web1HasModules = builtins.length (result.outputs.web-1.modules or [ ]) > 0;
            db1NoExtra = builtins.length (result.outputs.db-1.modules or [ ]) == 0;
          };
        expected = {
          web1HasModules = true;
          db1NoExtra = true;
        };
      };

      test-namespace-inheritance-in-pipeline = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.host;
                  nixos = { };
                }
              ];
              prod = {
                env = "production";
                web-1 = {
                  is = [ "host" ];
                };
              };
            };
          in
          result ? outputs && result.outputs ? web-1;
        expected = true;
      };

      test-needs-expansion-in-pipeline = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.nginx;
                  nixos = {
                    services.nginx.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  "host"
                  "server"
                ];
              };
            };
          in
          builtins.length (result.outputs.web-1.modules or [ ]) > 0;
        expected = true;
      };

      test-neededby-in-pipeline = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.monitoring;
                  nixos = {
                    services.monitoring.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  "host"
                  "server"
                ];
              };
            };
          in
          builtins.length (result.outputs.web-1.modules or [ ]) > 0;
        expected = true;
      };

      test-multiple-rules-collect-as-list = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.host;
                  nixos = {
                    a = 1;
                  };
                }
                {
                  is = traits.host;
                  nixos = {
                    b = 2;
                  };
                }
              ];
              igloo = {
                is = [ "host" ];
              };
            };
          in
          builtins.length (result.outputs.igloo.modules or [ ]);
        expected = 2;
      };

      test-has-selector-in-rule = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = [
                    traits.host
                    (sel.has traits.admin)
                  ];
                  nixos = {
                    security.sudo.enable = true;
                  };
                }
                {
                  is = traits.host;
                  nixos = { };
                }
              ];
              igloo = {
                is = [ "host" ];
                users.tux = {
                  is = [
                    "user"
                    "admin"
                  ];
                };
              };
              axon = {
                is = [ "host" ];
              };
            };
            iglooMods = builtins.length (result.outputs.igloo.modules or [ ]);
            axonMods = builtins.length (result.outputs.axon.modules or [ ]);
          in
          {
            iglooHasSudo = iglooMods == 2;
            axonNoSudo = axonMods == 1;
          };
        expected = {
          iglooHasSudo = true;
          axonNoSudo = true;
        };
      };

      test-child-contributions-bubble-up = {
        expr =
          let
            userBubbleT = {
              name = "user";
              class.homeManager = _select: modules: {
                nixos = modules;
              };
              needs = [ ];
              neededBy = [ ];
              synth = [ ];
            };
            result = nest.evalNest {
              traits = traits // {
                user = userBubbleT;
              };
              rules = [
                {
                  is = traits.host;
                  nixos = {
                    networking.hostName = "igloo";
                  };
                }
                {
                  is = userBubbleT;
                  homeManager = {
                    users.tux.shell = "/bin/zsh";
                  };
                }
              ];
              igloo = {
                is = [ "host" ];
                users.tux = {
                  is = [ userBubbleT ];
                };
              };
            };
          in
          {
            rootOnly = builtins.attrNames result.outputs == [ "igloo" ];
            hasUserConfig = builtins.any (m: m ? users) (result.outputs.igloo.modules or [ ]);
          };
        expected = {
          rootOnly = true;
          hasUserConfig = true;
        };
      };

      test-rule-synth = {
        expr =
          let
            result = nest.evalNest {
              inherit traits;
              rules = [
                {
                  is = traits.host;
                  synth = {
                    node.derived = "computed";
                  };
                }
                {
                  is = traits.host;
                  nixos = { };
                }
              ];
              igloo = {
                is = [ "host" ];
              };
            };
            node = builtins.head (builtins.filter (n: n.name == "igloo") result._nodes);
          in
          node.derived or null;
        expected = "computed";
      };
    };

  demo =
    let
      mockNixos = _select: modules: {
        _type = "nixos";
        inherit modules;
      };
      mockHm = _select: modules: {
        homeManager = modules;
      };
      traits = rec {
        host = {
          name = "host";
          class.nixos = mockNixos;
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
        };
        user = {
          name = "user";
          class.homeManager = mockHm;
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
        };
        server = {
          name = "server";
          needs = [ ssh ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        lb = {
          name = "lb";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        web = {
          name = "web";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        ssh = {
          name = "ssh";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        admin = {
          name = "admin";
          needs = [ ];
          neededBy = [ ];
          synth = [ ];
          class = { };
        };
        monitoring = {
          name = "monitoring";
          neededBy = [ server ];
          needs = [ ];
          synth = [ ];
          class = { };
        };
      };
      sel = nest.selectors;
      result = nest.evalNest {
        inherit traits;
        rules = [
          {
            is = traits.host;
            nixos = {
              boot.loader.grub.enable = true;
            };
          }
          {
            is = traits.server;
            nixos = {
              services.openssh.enable = true;
            };
          }
          {
            is = traits.lb;
            nixos =
              { select, ... }:
              {
                services.haproxy.backends = map (w: w.name) (select traits.web);
              };
          }
          {
            is = [
              traits.host
              (sel.has traits.admin)
            ];
            nixos = {
              security.sudo.enable = true;
            };
          }
          {
            is = traits.user;
            homeManager = {
              programs.git.enable = true;
            };
          }
        ];
        prod = {
          env = "production";
          lb = {
            is = [
              "host"
              "lb"
              "server"
            ];
          };
          web-1 = {
            is = [
              "host"
              "web"
              "server"
            ];
            users.alice = {
              is = [
                "user"
                "admin"
              ];
            };
          };
          web-2 = {
            is = [
              "host"
              "web"
              "server"
            ];
            users.bob = {
              is = [ "user" ];
            };
          };
        };
      };
    in
    {
      test-all-hosts-in-outputs = {
        expr = builtins.sort builtins.lessThan (builtins.attrNames result.outputs);
        expected = [
          "lb"
          "web-1"
          "web-2"
        ];
      };
      test-by-class-nixos = {
        expr = builtins.sort builtins.lessThan (builtins.attrNames (result.byClass.nixos or { }));
        expected = [
          "lb"
          "web-1"
          "web-2"
        ];
      };
      test-host-has-boot-config = {
        expr = builtins.any (m: m ? boot) (result.outputs.lb.modules or [ ]);
        expected = true;
      };
      test-server-has-ssh = {
        expr = builtins.any (m: m ? services && m.services ? openssh) (result.outputs.web-1.modules or [ ]);
        expected = true;
      };
      test-lb-has-haproxy-with-backends = {
        expr =
          let
            haproxyMods = builtins.filter (m: m ? services && m.services ? haproxy) (
              result.outputs.lb.modules or [ ]
            );
          in
          builtins.length haproxyMods > 0;
        expected = true;
      };
      test-web1-has-sudo = {
        expr = builtins.any (m: m ? security && m.security ? sudo) (result.outputs.web-1.modules or [ ]);
        expected = true;
      };
      test-web2-no-sudo = {
        expr = builtins.any (m: m ? security && m.security ? sudo) (result.outputs.web-2.modules or [ ]);
        expected = false;
      };
      test-neededby-monitoring-injected = {
        expr =
          let
            web1nodes = builtins.filter (n: n.name == "web-1") (result._nodes or [ ]);
            web1 = builtins.head web1nodes;
          in
          builtins.any (t: t.name == "monitoring") (web1.is or [ ]);
        expected = true;
      };
      test-users-are-child-nodes = {
        expr =
          let
            aliceNodes = builtins.filter (n: n.name == "alice") (result._nodes or [ ]);
          in
          builtins.length aliceNodes > 0 && !(result.outputs ? alice);
        expected = true;
      };
    };

  edge-cases =
    let
      mockNixos = _select: modules: {
        _type = "nixos";
        inherit modules;
      };
      hostT = {
        name = "host";
        class.nixos = mockNixos;
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
      };
      markerT = {
        name = "marker";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
    in
    {
      test-empty-dom = {
        expr =
          let
            result = nest.evalNest {
              traits = { };
              rules = [ ];
            };
          in
          result.outputs == { } && result.byClass == { };
        expected = true;
      };
      test-node-without-entity-trait-skipped = {
        expr =
          let
            result = nest.evalNest {
              traits = {
                marker = markerT;
              };
              rules = [ ];
              node = {
                is = [ markerT ];
              };
            };
          in
          result.outputs;
        expected = { };
      };
      test-css-string-selector-in-rule = {
        expr =
          let
            result = nest.evalNest {
              traits = {
                host = hostT;
              };
              rules = [
                {
                  is = "#igloo";
                  nixos = {
                    matched = true;
                  };
                }
              ];
              igloo = {
                is = [ hostT ];
              };
              axon = {
                is = [ hostT ];
              };
            };
          in
          {
            iglooMatched = builtins.length (result.outputs.igloo.modules or [ ]) > 0;
            axonNotMatched = builtins.length (result.outputs.axon.modules or [ ]) == 0;
          };
        expected = {
          iglooMatched = true;
          axonNotMatched = true;
        };
      };
      test-deep-namespace-nesting = {
        expr =
          let
            result = nest.evalNest {
              traits = {
                host = hostT;
              };
              rules = [
                {
                  is = hostT;
                  nixos = { };
                }
              ];
              dc1 = {
                region = "us";
                az = {
                  zone = "a";
                  prod = {
                    env = "prod";
                    web-1 = {
                      is = [ hostT ];
                    };
                  };
                };
              };
            };
          in
          result ? outputs && result.outputs ? web-1;
        expected = true;
      };
      test-multiple-nodes-same-level = {
        expr =
          let
            result = nest.evalNest {
              traits = {
                host = hostT;
              };
              rules = [
                {
                  is = hostT;
                  nixos = { };
                }
              ];
              a = {
                is = [ hostT ];
              };
              b = {
                is = [ hostT ];
              };
              c = {
                is = [ hostT ];
              };
            };
          in
          builtins.length (builtins.attrNames result.outputs);
        expected = 3;
      };
    };

  setup-tests = {
    test-trait-kind-has-options = {
      expr = nest.traitKind ? options;
      expected = true;
    };

    test-mk-rules-type = {
      expr =
        let
          rulesType = nest.mkRulesType { };
        in
        rulesType ? name;
      expected = true;
    };

    test-eval-nest-modules = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [ ];
          };
        in
        result ? schema && result ? rules;
      expected = true;
    };

    test-eval-nest-modules-with-schema = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              {
                schema.host = {
                  class = {
                    nixos = _: _: null;
                  };
                };
              }
            ];
          };
        in
        result.schema ? host;
      expected = true;
    };

    test-needs-selector-resolution = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.ssh = {
                    category = "security";
                  };
                  config.traits.firewall = {
                    category = "security";
                  };
                  config.traits.nginx = {
                    category = "web";
                  };
                  config.traits.server = {
                    needs = [
                      (nest.selectors.attrs { category = "security"; })
                    ];
                  };
                }
              )
            ];
          };
        in
        builtins.sort builtins.lessThan (map (t: t.name) result.traits.server.needs);
      expected = [
        "firewall"
        "ssh"
      ];
    };

    test-neededby-selector-resolution = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.host = {
                    class.nixos = _: _: null;
                  };
                  config.traits.server = { };
                  config.traits.monitoring = {
                    neededBy = [ "server" ];
                  };
                }
              )
            ];
          };
        in
        builtins.length result.traits.monitoring.neededBy > 0
        && (builtins.head result.traits.monitoring.neededBy).name == "server";
      expected = true;
    };

    test-setof-dedup = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.ssh = {
                    category = "security";
                  };
                  config.traits.server = {
                    needs = [
                      "ssh"
                      (nest.selectors.attrs { category = "security"; })
                    ];
                  };
                }
              )
            ];
          };
        in
        builtins.length result.traits.server.needs;
      expected = 1;
    };

    test-trait-attrs-matchable = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.ssh = {
                    category = "security";
                    port = 22;
                  };
                  config.traits.http = {
                    category = "web";
                    port = 80;
                  };
                  config.traits.server = {
                    needs = [
                      (nest.selectors.attrs { category = "security"; })
                    ];
                  };
                }
              )
            ];
          };
        in
        map (t: t.name) result.traits.server.needs;
      expected = [ "ssh" ];
    };

    test-self-need-validator = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.loop = {
                    needs = [ "loop" ];
                  };
                }
              )
            ];
          };
          ok = builtins.tryEval (builtins.deepSeq result.traits result);
        in
        ok.success;
      expected = false;
    };

    test-self-neededby-validator = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.loop = {
                    neededBy = [ "loop" ];
                  };
                }
              )
            ];
          };
          ok = builtins.tryEval (builtins.deepSeq result.traits result);
        in
        ok.success;
      expected = false;
    };

    test-nested-trait-structural-selector = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.web = { };
                  config.traits.api = { };
                  config.traits.server = {
                    needs = [
                      (nest.selectors.attrs { category = "frontend"; })
                    ];
                    category = "backend";
                  };
                  config.traits.nginx = {
                    category = "frontend";
                  };
                  config.traits.caddy = {
                    category = "frontend";
                  };
                }
              )
            ];
          };
        in
        builtins.sort builtins.lessThan (map (t: t.name) result.traits.server.needs);
      expected = [
        "caddy"
        "nginx"
      ];
    };

    test-refinement-rejects-underscore-name = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits._internal = { };
                }
              )
            ];
          };
          ok = builtins.tryEval (builtins.deepSeq result.traits result);
        in
        ok.success;
      expected = false;
    };

    test-refinement-allows-normal-name = {
      expr =
        let
          result = nest.evalNestModules {
            modules = [
              (
                { config, ... }:
                {
                  config.traits.server = { };
                }
              )
            ];
          };
          ok = builtins.tryEval (builtins.deepSeq result.traits result);
        in
        ok.success;
      expected = true;
    };
  };

  graph-queries =
    let
      inherit (nest) walkDom buildDomGraph;
      hostT = {
        name = "host";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class.nixos = _: _: null;
      };
      serverT = {
        name = "server";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      webT = {
        name = "web";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      lbT = {
        name = "lb";
        needs = [ ];
        neededBy = [ ];
        synth = [ ];
        class = { };
      };
      domNodes = walkDom {
        prod = {
          env = "production";
          lb = {
            is = [
              hostT
              lbT
              serverT
            ];
          };
          web-1 = {
            is = [
              hostT
              webT
              serverT
            ];
          };
          web-2 = {
            is = [
              hostT
              webT
              serverT
            ];
          };
        };
      };
      nodes = buildDomGraph domNodes;
    in
    {
      test-node-count = {
        expr = graphLib.sizeNodes nodes;
        expected = 3;
      };

      test-select-web-nodes = {
        expr =
          let
            webNodes = graphLib.select nodes (node: builtins.any (t: t.name == "web") (node.decls.is or [ ]));
          in
          builtins.sort builtins.lessThan (builtins.attrNames webNodes);
        expected = [
          "prod.web-1"
          "prod.web-2"
        ];
      };

      test-select-lb-node = {
        expr =
          let
            lbNodes = graphLib.select nodes (node: builtins.any (t: t.name == "lb") (node.decls.is or [ ]));
          in
          builtins.attrNames lbNodes;
        expected = [ "prod.lb" ];
      };

      test-all-nodes-are-leaves = {
        expr = builtins.sort builtins.lessThan (graphLib.leaves nodes);
        expected = [
          "prod.lb"
          "prod.web-1"
          "prod.web-2"
        ];
      };

      test-no-cycles = {
        expr = graphLib.cycles nodes;
        expected = [ ];
      };

      test-parent-edges-in-nested-dom = {
        expr =
          let
            userT = {
              name = "user";
              needs = [ ];
              neededBy = [ ];
              synth = [ ];
              class = { };
            };
            nestedNodes = walkDom {
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [ userT ];
                };
              };
            };
            nestedGraph = buildDomGraph nestedNodes;
            edgeSet = graphLib.fromEdges nestedGraph;
            pEdges = graphLib.selectEdges edgeSet (e: e.label == "P");
          in
          graphLib.sizeEdges pEdges;
        expected = 1;
      };

      test-flat-dom-no-parent-edges = {
        expr =
          let
            edgeSet = graphLib.fromEdges nodes;
          in
          graphLib.sizeEdges edgeSet;
        expected = 0;
      };

      test-import-graph-reachable = {
        expr =
          let
            importNodes = engine.buildNodes {
              importGraph = engine.overlays [
                (engine.vertices [
                  "lb"
                  "web-1"
                  "web-2"
                ])
                (engine.edge "lb" "web-1")
                (engine.edge "lb" "web-2")
              ];
            };
          in
          builtins.sort builtins.lessThan (graphLib.reachableFrom importNodes "lb");
        expected = [
          "web-1"
          "web-2"
        ];
      };

      test-import-graph-dependents = {
        expr =
          let
            importNodes = engine.buildNodes {
              importGraph = engine.overlays [
                (engine.vertices [
                  "lb"
                  "web-1"
                  "web-2"
                ])
                (engine.edge "lb" "web-1")
                (engine.edge "lb" "web-2")
              ];
            };
          in
          graphLib.dependents importNodes "web-1";
        expected = [ "lb" ];
      };
    };
}
