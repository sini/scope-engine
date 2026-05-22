{
  lib,
  schemaLib,
  aspects,
}:
{
  # Create the schema option with trait sidecars.
  mkTraitSchema =
    { classes ? { nixos = { }; homeManager = { }; } }:
    schemaLib.mkSchemaOption {
      sidecars = {
        needs = { default = [ ]; };
        neededBy = { default = [ ]; };
        synth = { default = [ ]; };
        class = { default = { }; };
      };
    };

  # Create the rules container type using gen-aspects.
  mkRulesType =
    { classes ? { nixos = { }; homeManager = { }; } }:
    aspects.aspectsType {
      inherit classes;
      aspectModules = [
        {
          options.is = lib.mkOption {
            type = lib.types.nullOr lib.types.raw;
            default = null;
            description = "Selector: trait, CSS string, selector attrset, or list (AND).";
          };
        }
      ];
    };

  # Evaluate user modules through gen-schema + gen-aspects, then extract config.
  evalNestModules =
    { modules, classes ? { nixos = { }; homeManager = { }; } }:
    let
      eval = lib.evalModules {
        modules = [
          {
            options.schema = schemaLib.mkSchemaOption {
              sidecars = {
                needs = { default = [ ]; };
                neededBy = { default = [ ]; };
                synth = { default = [ ]; };
                class = { default = { }; };
              };
            };
            options.rules = lib.mkOption {
              type = aspects.aspectsType {
                inherit classes;
                aspectModules = [
                  {
                    options.is = lib.mkOption {
                      type = lib.types.nullOr lib.types.raw;
                      default = null;
                    };
                  }
                ];
              };
              default = { };
            };
          }
        ] ++ modules;
      };
    in
    {
      schema = eval.config.schema;
      rules = eval.config.rules;
    };
}
