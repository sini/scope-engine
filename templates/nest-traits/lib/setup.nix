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
            candidateKeys = builtins.filter (
              k: !(builtins.elem k knownOptionKeys)
            ) (builtins.attrNames t);
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

  # Resolve a single raw ref value against the trait registry.
  # Returns a list (for concatMap): selectors expand to multiple, others to singleton.
  resolveRef =
    registry: v:
    if isSelector v then
      resolveSelector registry v
    else if builtins.isString v then
      if registry ? ${v} then
        [ registry.${v} ]
      else
        throw "nest: trait ref '${v}' not found (available: ${builtins.concatStringsSep ", " (builtins.attrNames registry)})"
    else
      [ v ];

  # Deduplicate trait instances by name (first-seen wins).
  dedupByName =
    vals:
    let
      step =
        seen: xs:
        if xs == [ ] then
          [ ]
        else
          let
            h = builtins.head xs;
            k = h.name;
            t = builtins.tail xs;
          in
          if seen ? ${k} then step seen t else [ h ] ++ step (seen // { ${k} = true; }) t;
    in
    step { } vals;

  traitKind = {
    options.needs = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Forward dependencies: trait refs, selectors, or strings (resolved at eval time).";
    };
    options.neededBy = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
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
  };

  # Post-evaluation derivation: resolves refs and selectors in needs/neededBy,
  # deduplicates, then validates. Runs after all instances are evaluated
  # (inside applyPipeline), breaking the cycle that refs-at-eval-time would cause.
  # Validation runs here (post-resolve) rather than in schema validators
  # (which fire pre-derive on unresolved values).
  mkTraitDerive =
    instances:
    let
      # Resolve refs and selectors, deduplicate by name
      resolve = field: instance:
        let
          raw = instance.${field} or [ ];
          resolved = builtins.concatMap (resolveRef instances) raw;
        in
        dedupByName resolved;

      derived = lib.mapAttrs (
        _name: instance:
        {
          needs = resolve "needs" instance;
          neededBy = resolve "neededBy" instance;
        }
      ) instances;

      # Post-resolve validation
      validate = name: instance:
        let
          resolvedNeeds = derived.${name}.needs;
          resolvedNeededBy = derived.${name}.neededBy;
        in
        if builtins.any (n: n.name == name) resolvedNeeds then
          throw "nest: trait '${name}' cannot need itself"
        else if builtins.any (n: n.name == name) resolvedNeededBy then
          throw "nest: trait '${name}' cannot inject into itself"
        else
          derived.${name};
    in
    lib.mapAttrs validate instances;

  mkTraitRegistry =
    schema: _traitsSelf:
    schemaLib.mkInstanceRegistry schema "trait" {
      strict = false;
      derive = mkTraitDerive;
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
