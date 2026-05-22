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
