{
  lib,
  schemaLib,
  aspects,
  selectorsLib,
}:
let
  isSelector = val: builtins.isAttrs val && val ? __sel;

  # Known option fields that are never sub-traits. Skipping these avoids
  # forcing needs/neededBy during selector resolution (which would recurse).
  knownOptionKeys = [
    "needs"
    "neededBy"
    "synth"
    "class"
    "name"
    "nodeId"
    "id_hash"
    "_module"
  ];

  # Build trait instances as matchable nodes for selector dispatch.
  # Trait attrs are directly matchable (no separate tags needed).
  # Nested traits (sub-attrsets with nodeId) get parent edges for :has/:within.
  buildTraitNodes =
    traits:
    let
      allInstances = builtins.attrValues traits;
      walk =
        parentPath: instances:
        builtins.concatMap (
          t:
          let
            node = t // {
              __path = t.name;
              __parentPath = parentPath;
              is = [ ];
            };
            candidateKeys = builtins.filter (k: !(builtins.elem k knownOptionKeys)) (builtins.attrNames t);
            subTraitNames = builtins.filter (
              k:
              let
                v = t.${k} or null;
              in
              v != null && builtins.isAttrs v && v ? nodeId
            ) candidateKeys;
            children = walk t.name (map (k: t.${k}) subTraitNames);
          in
          [ node ] ++ children
        ) instances;
    in
    walk null allInstances;

  resolveSelector =
    traits: sel:
    let
      traitNodes = buildTraitNodes traits;
      matches = builtins.filter (
        t: selectorsLib.matchesOne t sel (selectorsLib.mkCtx t traitNodes)
      ) traitNodes;
    in
    map (t: traits.${t.name}) matches;

  traitKind = {
    options.needs = lib.mkOption {
      type = schemaLib.setOf (schemaLib.ref "trait");
      default = [ ];
      description = "Forward dependencies: trait refs, selectors, or strings (resolved at eval time).";
    };
    options.neededBy = lib.mkOption {
      type = schemaLib.setOf (schemaLib.ref "trait");
      default = [ ];
      description = "Reverse injection: trait refs, selectors, or strings (resolved at eval time).";
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
    validators = [
      (schemaLib.mkValidator "no-self-need"
        ({ name, needs, ... }: !builtins.any (n: n.name == name) needs)
        "trait cannot need itself"
      )
      (schemaLib.mkValidator "no-self-neededby"
        ({ name, neededBy, ... }: !builtins.any (n: n.name == name) neededBy)
        "trait cannot inject into itself"
      )
    ];
  };

  mkTraitRegistry =
    schema: traitsSelf:
    let
      coerceHook = {
        instances = traitsSelf;
        deferred = true;
        coerce = registry: default: val: if isSelector val then resolveSelector registry val else default;
      };
    in
    schemaLib.mkInstanceRegistry schema "trait" {
      strict = false;
      refs = {
        needs = coerceHook;
        neededBy = coerceHook;
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
    buildTraitNodes
    resolveSelector
    isSelector
    ;
}
