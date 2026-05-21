{ lib, engine, ... }:
let
  baseNodes = engine.buildNodes {
    parentGraph = engine.vertices [
      "full"
      "partial"
      "empty"
    ];
    decls = {
      full = {
        a = 1;
        b = 2;
        c = 3;
      };
      partial = {
        a = 1;
        b = 2;
      };
      empty = { };
    };
  };

  result = engine.eval {
    inherit baseNodes;
    attributes = { };
  };
in
{
  subtype = {
    test-subset-is-subtype = {
      expr = engine.subtypeOf { } result "partial" "full";
      expected = true;
    };

    test-superset-is-not-subtype = {
      expr = engine.subtypeOf { } result "full" "partial";
      expected = false;
    };

    test-empty-is-subtype-of-all = {
      expr = engine.subtypeOf { } result "empty" "full";
      expected = true;
    };

    test-self-is-subtype = {
      expr = engine.subtypeOf { } result "full" "full";
      expected = true;
    };

    test-custom-eq = {
      expr =
        let
          n = engine.buildNodes {
            parentGraph = engine.vertices [
              "a"
              "b"
            ];
            decls = {
              a = {
                x = 1;
              };
              b = {
                x = 2;
              };
            };
          };
          r = engine.eval {
            baseNodes = n;
            attributes = { };
          };
        in
        {
          # Default eq (always true) — only checks key presence.
          key-only = engine.subtypeOf { } r "a" "b";
          # Value eq — checks actual values.
          value-eq = engine.subtypeOf { eq = _k: a: b: a == b; } r "a" "b";
        };
      expected = {
        key-only = true;
        value-eq = false;
      };
    };
  };
}
