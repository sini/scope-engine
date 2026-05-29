{
  lib,
  genScope,
  genSchema,
  aspects,
  genAlgebra,
}:
let
  css = import ./css.nix;
  selectorsLib = import ./selectors.nix { inherit lib genScope; };
  dom = import ./dom.nix { inherit lib genScope; };
  traitsLib = import ./traits.nix {
    inherit lib genScope selectorsLib;
  };
  enginePipeline = import ./engine.nix {
    inherit
      lib
      genScope
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
    deepMerge
    ;
  inherit css;
  selectors = selectorsLib.constructors;
  inherit
    (import ./setup.nix {
      inherit
        lib
        genSchema
        aspects
        selectorsLib
        ;
    })
    traitKind
    mkTraitRegistry
    mkRulesType
    evalNestModules
    buildTraitNodes
    resolveSelector
    isSelector
    ;
}
