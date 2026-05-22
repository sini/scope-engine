{
  lib,
  engine,
  selectorsLib,
}:
{
  expandTraits =
    _: _: _:
    [ ];
  expandNeededBy =
    _: _: _: _:
    [ ];
  applySynth = _: _: _: _: {
    node = { };
    children = [ ];
  };
  deepMerge = a: b: a // b;
  flattenTraitTree = _: [ ];
  traitSpecialKeys = [ ];
}
