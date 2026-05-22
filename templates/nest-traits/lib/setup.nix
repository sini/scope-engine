{
  lib,
  schemaLib,
  aspects,
}:
let
  traitKind = {
    options.needs = lib.mkOption {
      type = lib.types.listOf (schemaLib.ref "trait");
      default = [ ];
      description = "Forward trait dependencies (BFS expanded).";
    };
    options.neededBy = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Reverse injection selectors. Each entry: trait instance, trait name string, CSS string, or selector attrset.";
    };
    options.synth = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Synthesis functions. Folded in order, results deep-merged.";
    };
    options.class = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
      description = "Output class builders. { className = select: modules: value; }";
    };
  };

  mkTraitRegistry =
    schema: traitsSelf:
    schemaLib.mkInstanceRegistry schema "trait" {
      refs = {
        trait = traitsSelf;
      };
    };

  mkRulesType =
    {
      classes ? {
        nixos = { };
        homeManager = { };
      },
    }:
    aspects.aspectsType {
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

  evalNestModules =
    {
      modules,
      classes ? {
        nixos = { };
        homeManager = { };
      },
    }:
    let
      eval = lib.evalModules {
        modules = [
          (
            { config, ... }:
            {
              options.schema = schemaLib.mkSchemaOption { };
              config.schema.trait = traitKind;
              options.traits = mkTraitRegistry config.schema config.traits;
              options.rules = lib.mkOption {
                type = mkRulesType { inherit classes; };
                default = { };
              };
            }
          )
        ]
        ++ modules;
      };
    in
    {
      traits = eval.config.traits;
      rules = eval.config.rules;
      schema = eval.config.schema;
    };
in
{
  inherit
    traitKind
    mkTraitRegistry
    mkRulesType
    evalNestModules
    ;
}
