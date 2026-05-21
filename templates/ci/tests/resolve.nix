{ lib, engine, ... }:
{
  resolve = {
    test-shadow-inner-wins = {
      expr = engine.shadow { a = 1; b = 2; } { a = 99; c = 3; };
      expected = {
        a = 1;
        b = 2;
        c = 3;
      };
    };

    test-shadow-no-overlap = {
      expr = engine.shadow { a = 1; } { b = 2; };
      expected = {
        a = 1;
        b = 2;
      };
    };

    test-resolve-local-wins = {
      expr = engine.resolve {
        local = "local";
        imported = "imported";
        inherited = "inherited";
      };
      expected = "local";
    };

    test-resolve-import-over-parent = {
      expr = engine.resolve {
        imported = "imported";
        inherited = "inherited";
      };
      expected = "imported";
    };

    test-resolve-fallback-to-inherited = {
      expr = engine.resolve { inherited = "inherited"; };
      expected = "inherited";
    };

    test-resolve-all-null = {
      expr = engine.resolve { };
      expected = null;
    };
  };
}
