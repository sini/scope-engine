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

  selectors =
    let
      hostTrait = {
        __traitName = "host";
        class = {
          nixos = _: _: null;
        };
      };
      userTrait = {
        __traitName = "user";
      };
      serverTrait = {
        __traitName = "server";
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
      mkTrait = name: extra: { __traitName = name; } // extra;
      hostT = mkTrait "host" { class.nixos = _: _: null; };
      serverT = mkTrait "server" {
        needs = [
          nginxT
          firewallT
        ];
      };
      nginxT = mkTrait "nginx" { };
      firewallT = mkTrait "firewall" { };
      monitoringT = mkTrait "monitoring" { neededBy = [ serverT ]; };
      webT = mkTrait "web" { needs = [ serverT ]; };
      circularA = mkTrait "circA" { needs = [ circularB ]; };
      circularB = mkTrait "circB" { needs = [ circularA ]; };

      processedTraits = {
        host = hostT;
        server = serverT;
        nginx = nginxT;
        firewall = firewallT;
        monitoring = monitoringT;
        web = webT;
      };

      inherit (nest) expandTraits expandNeededBy;
      traitNames = ts: map (t: t.__traitName) ts;
    in
    {
      test-no-needs = {
        expr = traitNames (expandTraits processedTraits [ hostT ] [ ]);
        expected = [ "host" ];
      };
      test-direct-needs = {
        expr = builtins.sort builtins.lessThan (traitNames (expandTraits processedTraits [ serverT ] [ ]));
        expected = [
          "firewall"
          "nginx"
          "server"
        ];
      };
      test-transitive-needs = {
        expr = builtins.sort builtins.lessThan (traitNames (expandTraits processedTraits [ webT ] [ ]));
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
            expanded =
              expandTraits processedTraits
                [
                  webT
                  serverT
                ]
                [ ];
            names = traitNames expanded;
          in
          builtins.length (builtins.filter (n: n == "server") names);
        expected = 1;
      };
      test-circular-needs-safe = {
        expr =
          let
            expanded = expandTraits processedTraits [ circularA ] [ ];
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
            node = {
              name = "web-1";
              __path = "web-1";
              __parentPath = null;
              is = [
                hostT
                serverT
              ];
            };
            allNodes = [ node ];
            expanded = expandNeededBy processedTraits [
              hostT
              serverT
            ] node allNodes;
          in
          builtins.any (t: t.__traitName == "monitoring") expanded;
        expected = true;
      };
      test-neededby-no-match = {
        expr =
          let
            node = {
              name = "web-1";
              __path = "web-1";
              __parentPath = null;
              is = [ hostT ];
            };
            allNodes = [ node ];
            expanded = expandNeededBy processedTraits [ hostT ] node allNodes;
          in
          builtins.any (t: t.__traitName == "monitoring") expanded;
        expected = false;
      };
      test-needs-as-function = {
        expr =
          let
            dynT = mkTrait "dynamic" { needs = traits: [ traits.nginx ]; };
            expanded = expandTraits processedTraits [ dynT ] [ ];
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
      mkTrait = name: extra: { __traitName = name; } // extra;
      mockNixos = _select: modules: {
        _type = "nixos";
        modules = modules;
      };
      mockHm = _select: modules: {
        _type = "hm";
        modules = modules;
      };
      hostT = mkTrait "host" { class.nixos = mockNixos; };
      userT = mkTrait "user" { class.homeManager = mockHm; };
      serverT = mkTrait "server" { needs = [ nginxT ]; };
      nginxT = mkTrait "nginx" { };
      adminT = mkTrait "admin" { };
      monitoringT = mkTrait "monitoring" { neededBy = [ serverT ]; };
      processedTraits = {
        host = hostT;
        user = userT;
        server = serverT;
        nginx = nginxT;
        admin = adminT;
        monitoring = monitoringT;
      };
      sel = nest.selectors;
    in
    {
      test-basic-output = {
        expr =
          let
            result = nest.evalNest {
              trait = processedTraits;
              rules = [
                {
                  is = hostT;
                  nixos = {
                    networking.hostName = "test";
                  };
                }
              ];
              igloo = {
                is = [ hostT ];
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
              trait = processedTraits;
              rules = [
                {
                  is = hostT;
                  nixos = {
                    networking.hostName = "test";
                  };
                }
              ];
              igloo = {
                is = [ hostT ];
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
              trait = processedTraits;
              rules = [
                {
                  is = serverT;
                  nixos = {
                    services.nginx.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  hostT
                  serverT
                ];
              };
              db-1 = {
                is = [ hostT ];
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
              trait = processedTraits;
              rules = [
                {
                  is = hostT;
                  nixos = { };
                }
              ];
              prod = {
                env = "production";
                web-1 = {
                  is = [ hostT ];
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
              trait = processedTraits;
              rules = [
                {
                  is = nginxT;
                  nixos = {
                    services.nginx.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  hostT
                  serverT
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
              trait = processedTraits;
              rules = [
                {
                  is = monitoringT;
                  nixos = {
                    services.monitoring.enable = true;
                  };
                }
              ];
              web-1 = {
                is = [
                  hostT
                  serverT
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
              trait = processedTraits;
              rules = [
                {
                  is = hostT;
                  nixos = {
                    a = 1;
                  };
                }
                {
                  is = hostT;
                  nixos = {
                    b = 2;
                  };
                }
              ];
              igloo = {
                is = [ hostT ];
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
              trait = processedTraits;
              rules = [
                {
                  is = [
                    hostT
                    (sel.has adminT)
                  ];
                  nixos = {
                    security.sudo.enable = true;
                  };
                }
                {
                  is = hostT;
                  nixos = { };
                }
              ];
              igloo = {
                is = [ hostT ];
                users.tux = {
                  is = [
                    userT
                    adminT
                  ];
                };
              };
              axon = {
                is = [ hostT ];
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
    };

  demo =
    let
      mockNixos = _select: modules: {
        _type = "nixos";
        inherit modules;
      };
      mockHm = _select: modules: {
        _type = "hm";
        inherit modules;
      };
      mkTrait = name: extra: { __traitName = name; } // extra;
      hostT = mkTrait "host" { class.nixos = mockNixos; };
      userT = mkTrait "user" { class.homeManager = mockHm; };
      serverT = mkTrait "server" { needs = [ sshT ]; };
      lbT = mkTrait "lb" { };
      webT = mkTrait "web" { };
      sshT = mkTrait "ssh" { };
      adminT = mkTrait "admin" { };
      monitoringT = mkTrait "monitoring" { neededBy = [ serverT ]; };
      processedTraits = {
        host = hostT;
        user = userT;
        server = serverT;
        lb = lbT;
        web = webT;
        ssh = sshT;
        admin = adminT;
        monitoring = monitoringT;
      };
      sel = nest.selectors;
      result = nest.evalNest {
        trait = processedTraits;
        rules = [
          {
            is = hostT;
            nixos = {
              boot.loader.grub.enable = true;
            };
          }
          {
            is = serverT;
            nixos = {
              services.openssh.enable = true;
            };
          }
          {
            is = lbT;
            nixos =
              { select, ... }:
              {
                services.haproxy.backends = map (w: w.name) (select webT);
              };
          }
          {
            is = [
              hostT
              (sel.has adminT)
            ];
            nixos = {
              security.sudo.enable = true;
            };
          }
          {
            is = userT;
            homeManager = {
              programs.git.enable = true;
            };
          }
        ];
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
            users.alice = {
              is = [
                userT
                adminT
              ];
            };
          };
          web-2 = {
            is = [
              hostT
              webT
              serverT
            ];
            users.bob = {
              is = [ userT ];
            };
          };
        };
      };
    in
    {
      test-all-hosts-in-outputs = {
        expr = builtins.sort builtins.lessThan (builtins.attrNames result.outputs);
        expected = [
          "alice"
          "bob"
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
      test-by-class-hm = {
        expr = builtins.sort builtins.lessThan (builtins.attrNames (result.byClass.homeManager or { }));
        expected = [
          "alice"
          "bob"
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
          builtins.any (t: t.__traitName == "monitoring") (web1.is or [ ]);
        expected = true;
      };
      test-user-has-hm-output = {
        expr = builtins.any (m: m ? programs && m.programs ? git) (result.outputs.alice.modules or [ ]);
        expected = true;
      };
    };

  edge-cases =
    let
      mkTrait = name: extra: { __traitName = name; } // extra;
      mockNixos = _select: modules: {
        _type = "nixos";
        inherit modules;
      };
      hostT = mkTrait "host" { class.nixos = mockNixos; };
      markerT = mkTrait "marker" { };
    in
    {
      test-empty-dom = {
        expr =
          let
            result = nest.evalNest {
              trait = { };
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
              trait = {
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
              trait = {
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
              trait = {
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
              trait = {
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
}
