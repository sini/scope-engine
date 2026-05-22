{
  lib,
  engine,
  schemaLib,
  aspects,
}:
let
  css = import ./css.nix;
  selectorsLib = import ./selectors.nix { inherit lib engine; };
  dom = import ./dom.nix { inherit lib engine; };
  traitsLib = import ./traits.nix {
    inherit lib engine selectorsLib;
  };
  enginePipeline = import ./engine.nix {
    inherit
      lib
      engine
      dom
      selectorsLib
      traitsLib
      ;
  };
in
{
  inherit (enginePipeline) evalNest;
  inherit (selectorsLib)
    matchesOne
    matchesSel
    callWithArgs
    mkCtx
    ;
  inherit (dom) walkDom buildDomGraph;
  inherit (traitsLib)
    expandTraits
    expandNeededBy
    applySynth
    flattenTraitTree
    deepMerge
    ;
  inherit css;
  selectors = selectorsLib.constructors;
  inherit
    (import ./setup.nix {
      inherit lib schemaLib aspects;
    })
    mkTraitSchema
    mkRulesType
    evalNestModules
    ;
}
