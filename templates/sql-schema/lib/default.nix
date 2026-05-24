{
  lib,
  engine,
  schemaLib,
  graphLib,
  genLib,
}:
let
  rawFleet = import ./fleet.nix;
  schemaModule = import ./schema.nix { inherit lib schemaLib; };
  evaluated = schemaModule.evalSchema rawFleet;

  # Graph construction: kind-level and instance-level
  kindGraphInputs = schemaLib.buildKindGraph evaluated.schema;
  kindNodes = engine.buildNodes kindGraphInputs;

  instanceGraphInputs = schemaLib.buildInstanceGraph evaluated.schema evaluated.fleet;
  instanceNodes = engine.buildNodes instanceGraphInputs;

  # SQL parser
  sqlParser = import ./sql.nix { inherit lib; };
in
{
  inherit (schemaModule) refinements validators;
  inherit (evaluated) schema fleet;
  evalSchema = schemaModule.evalSchema;
  inherit rawFleet;

  # Graph API
  inherit kindNodes instanceNodes;
  inherit kindGraphInputs instanceGraphInputs;

  # gen-graph queries on kind-level graph
  kindRoots = graphLib.roots kindNodes;
  kindLeaves = graphLib.leaves kindNodes;
  kindCycles = graphLib.cycles kindNodes;
  kindMigrationOrder = graphLib.roots kindNodes;

  # gen-graph queries on instance-level graph
  reachableFrom = graphLib.reachableFrom instanceNodes;
  dependents = graphLib.dependents instanceNodes;
  impactOf = graphLib.impactOf instanceNodes;

  # SQL parser
  inherit (sqlParser) parseSql tokenize;
}
