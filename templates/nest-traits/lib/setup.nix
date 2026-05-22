{
  lib,
  schemaLib,
  aspects,
}:
{
  mkTraitSchema = _: { };
  mkRulesType = _: lib.types.raw;
  evalNestModules = _: {
    schema = { };
    rules = { };
  };
}
