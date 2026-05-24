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

  # SQL parser + engine
  sqlParser = import ./sql.nix { inherit lib; };
  sqlEngine = import ./engine.nix { inherit lib; };

  # DDL generator
  ddlLib = import ./ddl.nix { inherit lib schemaLib; };
  ddl = ddlLib.generateDDL evaluated.schema;

  # Synthesis
  aclLib = import ./acl.nix { inherit lib; };
  reachLib = import ./reachability.nix { inherit lib; };
  effectiveAccess = aclLib.synthesizeAccess rawFleet;
  networkReachability = reachLib.synthesizeReachability rawFleet;
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

  # SQL parser + engine
  inherit (sqlParser) parseSql tokenize;
  query = sqlEngine.query rawFleet;
  queryFleet = sqlEngine.query;

  # DDL
  inherit ddl;
  generateDDL = ddlLib.generateDDL;
  migrationOrder = ddlLib.migrationOrder evaluated.schema;
  inherit (ddlLib) escapeIdent;

  # Synthesis
  inherit effectiveAccess networkReachability;
  synthesizeAccess = aclLib.synthesizeAccess;
  synthesizeReachability = reachLib.synthesizeReachability;
}
