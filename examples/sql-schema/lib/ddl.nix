# DDL generator — produces migration-ordered CREATE TABLE statements.
#
# Reads schema metadata to emit columns with types, FK constraints,
# CHECK constraints from refinements, and indexes from ref fields.
{ lib, genSchema }:
let
  # SQL reserved words that need escaping
  reservedWords = [
    "user"
    "primary"
    "group"
    "order"
    "table"
    "index"
    "type"
    "name"
  ];

  # Escape identifier: hyphen → underscore, reserved words → suffixed with _
  escapeIdent =
    name:
    let
      underscored = builtins.replaceStrings [ "-" ] [ "_" ] name;
    in
    if builtins.elem underscored reservedWords then "${underscored}_" else underscored;

  # Map Nix option types to SQL types
  nixTypeToSql =
    optType:
    let
      typeName = optType.name or "unknown";
    in
    if typeName == "str" then
      "text"
    else if typeName == "int" then
      "int"
    else if typeName == "bool" then
      "boolean"
    else if lib.hasPrefix "listOf" typeName then
      "text[]"
    else if lib.hasPrefix "nullOr" typeName then
      nixTypeToSql ((optType.nestedTypes or { }).elemType or { name = "text"; })
    else if lib.hasPrefix "ref" typeName then
      "text"
    else if lib.hasPrefix "setOf" typeName then
      null # junction table instead
    else
      "text";

  # Check if an option type is nullable (nullOr)
  isNullable =
    optType:
    let
      typeName = optType.name or "";
    in
    lib.hasPrefix "nullOr" typeName;

  # Check if an option type is a setOf (produces junction table)
  isSetOf = optType: optType.isSetOf or false;

  # Determine if a ref field produces a junction table
  isJunctionRef = optType: isSetOf optType || (lib.hasPrefix "setOf" (optType.name or ""));

  # Generate CHECK constraints from enum refinements
  mkCheckConstraint =
    fieldName: refinementList:
    let
      enumChecks = builtins.filter (
        r:
        let
          msg = r.message or "";
        in
        lib.hasPrefix "must be " msg && builtins.match ".*,.*" msg != null
      ) refinementList;
      rangeChecks = builtins.filter (
        r:
        let
          msg = r.message or "";
        in
        lib.hasPrefix "must be positive" msg
        || lib.hasPrefix "must be a valid TCP" msg
        || lib.hasPrefix "VLAN ID" msg
      ) refinementList;
    in
    # For known enum refinements, produce CHECK constraints
    lib.optionals (enumChecks != [ ]) (
      map (_: "CHECK (${escapeIdent fieldName} IN (/* see schema */))") enumChecks
    )
    ++ lib.optionals (rangeChecks != [ ]) (
      map (
        r:
        let
          msg = r.message or "";
        in
        if lib.hasPrefix "must be positive" msg then
          "CHECK (${escapeIdent fieldName} > 0)"
        else if lib.hasPrefix "must be a valid TCP" msg then
          "CHECK (${escapeIdent fieldName} >= 1 AND ${escapeIdent fieldName} <= 65535)"
        else if lib.hasPrefix "VLAN ID" msg then
          "CHECK (${escapeIdent fieldName} >= 1 AND ${escapeIdent fieldName} <= 4094)"
        else
          ""
      ) rangeChecks
    );

  # Generate a CREATE TABLE statement for one kind
  generateTable =
    schema: kindName:
    let
      kindResult = schema.${kindName};
      refs = lib.mapAttrs (_: v: v.refKind) kindResult.refs;
      tableName = escapeIdent kindName;

      # Option names minus internal ones
      optNames = builtins.filter (
        n:
        !(builtins.elem n [
          "name"
          "nodeId"
          "id_hash"
          "_module"
        ])
      ) (builtins.attrNames kindResult.options);

      # Build column definitions
      columns = builtins.concatMap (
        optName:
        let
          opt = kindResult.options.${optName};
          optType = opt.type or { name = "text"; };
          sqlType = nixTypeToSql optType;
          nullable = isNullable optType;
          colName = escapeIdent optName;
          isRef = refs ? ${optName};
          refTarget = if isRef then escapeIdent refs.${optName} else null;
        in
        # Skip setOf fields (they become junction tables)
        if sqlType == null || isJunctionRef optType then
          [ ]
        else
          [
            {
              col = colName;
              sqlType = sqlType;
              constraints =
                lib.optional (!nullable) "NOT NULL" ++ lib.optional isRef "REFERENCES ${refTarget}(name_)";
            }
          ]
      ) optNames;

      # Junction tables for setOf refs
      junctionTables = builtins.concatMap (
        optName:
        let
          opt = kindResult.options.${optName};
          optType = opt.type or { name = "text"; };
        in
        if isJunctionRef optType && refs ? ${optName} then
          [
            {
              tableName = "${tableName}_${escapeIdent optName}";
              leftCol = tableName;
              rightCol = escapeIdent refs.${optName};
              leftRef = tableName;
              rightRef = escapeIdent refs.${optName};
            }
          ]
        else
          [ ]
      ) optNames;

      # Render column lines
      columnLines = [
        "  name_ text PRIMARY KEY NOT NULL"
      ]
      ++ map (
        c:
        "  ${c.col} ${c.sqlType}${
            if c.constraints != [ ] then " " + builtins.concatStringsSep " " c.constraints else ""
          }"
      ) columns;

      tableStmt = ''
        CREATE TABLE ${tableName} (
        ${builtins.concatStringsSep ",\n" columnLines}
        );'';

      junctionStmts = map (jt: ''
        CREATE TABLE ${jt.tableName} (
          ${jt.leftCol} text NOT NULL REFERENCES ${jt.leftRef}(name_),
          ${jt.rightCol} text NOT NULL REFERENCES ${jt.rightRef}(name_),
          PRIMARY KEY (${jt.leftCol}, ${jt.rightCol})
        );'') junctionTables;
    in
    [ tableStmt ] ++ junctionStmts;

  # Generate indexes for FK columns
  generateIndexes =
    schema: kindName:
    let
      refs = lib.mapAttrs (_: v: v.refKind) schema.${kindName}.refs;
      tableName = escapeIdent kindName;
    in
    lib.mapAttrsToList (
      field: _target:
      let
        colName = escapeIdent field;
      in
      "CREATE INDEX idx_${tableName}_${colName} ON ${tableName}(${colName});"
    ) refs;

  # Generate views for synthesized kinds
  generateViews = _schema: [
    ''
      CREATE VIEW user_permissions AS
        SELECT name_ AS username, resource, actions, via
        FROM effective_access;''
    ''
      CREATE VIEW server_network_map AS
        SELECT s.name_ AS server, i.ip, i.mac, v.name_ AS vlan, sub.cidr AS subnet
        FROM server s
        JOIN interface i ON i.server = s.name_ AND i.primary_ = true
        JOIN vlan v ON i.vlan = v.name_
        JOIN subnet sub ON v.subnet = sub.name_;''
  ];

  # Topological sort for migration ordering (roots first)
  migrationOrder =
    schema:
    let
      kindNames = schema._kindNames;

      # Build dependency map: kind → [kinds it depends on via refs and parent]
      deps = lib.genAttrs kindNames (
        k:
        let
          refTargets = map (v: v.refKind) (builtins.attrValues schema.${k}.refs);
          parentDep = schema._topology.${k}.parent;
        in
        # Filter out self-refs (they don't create ordering constraints)
        builtins.filter (dep: dep != k) (
          lib.unique (refTargets ++ lib.optional (parentDep != null) parentDep)
        )
      );

      # Kahn's algorithm
      go =
        ordered: remaining:
        if remaining == [ ] then
          ordered
        else
          let
            # Find kinds with all dependencies satisfied
            ready = builtins.filter (k: builtins.all (dep: builtins.elem dep ordered) deps.${k}) remaining;
          in
          if ready == [ ] then
            # Remaining kinds have circular deps — emit them anyway
            ordered ++ (builtins.sort builtins.lessThan remaining)
          else
            go (ordered ++ builtins.sort builtins.lessThan ready) (
              builtins.filter (k: !(builtins.elem k ready)) remaining
            );
    in
    go [ ] kindNames;

  # Generate full DDL in migration order
  generateDDL =
    schema:
    let
      order = migrationOrder schema;
      tables = builtins.concatMap (k: generateTable schema k) order;
      indexes = builtins.concatMap (k: generateIndexes schema k) order;
      views = generateViews schema;
    in
    {
      inherit
        tables
        indexes
        views
        order
        ;
      full = builtins.concatStringsSep "\n\n" (tables ++ [ "" ] ++ indexes ++ [ "" ] ++ views);
    };

in
{
  inherit
    generateDDL
    generateTable
    generateIndexes
    generateViews
    migrationOrder
    escapeIdent
    ;
}
