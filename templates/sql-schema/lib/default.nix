{
  lib,
  engine,
  schemaLib,
  graphLib,
  genLib,
}:
let
  rawFleet = import ./fleet.nix;
  schema = import ./schema.nix { inherit lib schemaLib; };
  evaluated = schema.evalSchema rawFleet;
in
{
  inherit (schema) refinements validators;
  inherit (evaluated) schema fleet;
  evalSchema = schema.evalSchema;
  rawFleet = rawFleet;
}
