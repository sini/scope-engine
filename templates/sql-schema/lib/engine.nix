# SQL query engine — evaluates parsed ASTs against fleet data.
#
# JOINs are resolved via FK field lookup in instance registries.
# WHERE predicates filter rows. ORDER BY sorts. LIMIT truncates.
{ lib }:
let
  # Kind name normalization: SQL uses plural/underscored table names,
  # fleet data uses singular/hyphenated kind names.
  # Map common SQL table names to fleet kind names.
  kindAliases = {
    servers = "server";
    interfaces = "interface";
    services = "service";
    ports = "port";
    networks = "network";
    subnets = "subnet";
    vlans = "vlan";
    datacenters = "datacenter";
    environments = "environment";
    domains = "domain";
    dns_records = "dns-record";
    loadbalancers = "loadbalancer";
    backends = "backend";
    firewall_rules = "firewall-rule";
    certificates = "certificate";
    schedules = "schedule";
    ldap_groups = "ldap-group";
    ldap_roles = "ldap-role";
    users = "user";
    access_policies = "access-policy";
    service_dependencies = "service-dependency";
    effective_access = "effective-access";
    network_reachability = "network-reachability";
  };

  resolveKind = name:
    kindAliases.${name} or name;

  # Get rows from fleet: { name → row } with name injected
  getRows = fleet: kindName:
    let kind = resolveKind kindName;
    in lib.mapAttrs (name: row:
      (if builtins.isAttrs row then row else {}) // { inherit name; }
    ) (fleet.${kind} or {});

  # Resolve a field value from a row, handling ref instances (extract .name)
  getField = row: fieldName:
    let
      raw = row.${fieldName} or null;
    in
    if raw == null then null
    else if builtins.isAttrs raw && raw ? name then raw.name
    else if builtins.isList raw && builtins.length raw > 0 && builtins.isAttrs (builtins.head raw) then
      map (x: if builtins.isAttrs x && x ? name then x.name else x) raw
    else raw;

  # Evaluate a WHERE predicate against a row with alias resolution
  evalWhere = aliases: row: expr:
    if expr == null then true
    else if expr.op == "AND" then
      evalWhere aliases row expr.left && evalWhere aliases row expr.right
    else if expr.op == "OR" then
      evalWhere aliases row expr.left || evalWhere aliases row expr.right
    else if expr.op == "=" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv == rv
    else if expr.op == "!=" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv != rv
    else if expr.op == ">" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv > rv
    else if expr.op == ">=" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv >= rv
    else if expr.op == "<" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv < rv
    else if expr.op == "<=" then
      let
        lv = resolveValue aliases row expr.left;
        rv = resolveValue aliases row expr.right;
      in lv <= rv
    else if expr.op == "LIKE" then
      let
        lv = resolveValue aliases row expr.left;
        pattern = expr.right;
        # Convert SQL LIKE pattern to Nix regex: % → .*, _ → ., escape rest
        toRegex = p:
          let
            chars = lib.stringToCharacters p;
            converted = map (c:
              if c == "%" then ".*"
              else if c == "_" then "."
              else if builtins.elem c [ "." "^" "$" "[" "]" "(" ")" "{" "}" "\\" "+" "?" "|" ] then "\\${c}"
              else c
            ) chars;
          in
          lib.concatStrings converted;
        regex = toRegex pattern;
      in
      builtins.isString lv && builtins.match regex lv != null
    else if expr.op == "IN" then
      let
        lv = resolveValue aliases row expr.left;
        rv = expr.right;
      in
      # Forward: column IN (values)
      if builtins.isList rv then
        if builtins.isList lv then
          builtins.any (item: builtins.elem item rv) lv
        else
          builtins.elem lv rv
      # Reverse: 'value' IN column (column is a list)
      else if builtins.isList lv then
        builtins.elem rv lv
      else lv == rv
    else if expr.op == "IS NULL" then
      resolveValue aliases row expr.left == null
    else if expr.op == "IS NOT NULL" then
      resolveValue aliases row expr.left != null
    else throw "sql-engine: unsupported WHERE operator '${expr.op}'";

  # Resolve a value reference (column ref or literal)
  resolveValue = aliases: row: ref:
    if builtins.isString ref then ref
    else if builtins.isInt ref then ref
    else if builtins.isBool ref then ref
    else if builtins.isAttrs ref && ref ? column then
      let
        targetRow =
          if ref.table != null && aliases ? ${ref.table} then
            aliases.${ref.table}
          else row;
      in
      getField targetRow ref.column
    else ref;

  # Resolve a JOIN: for each row in leftRows, find matching rows in the joined kind
  resolveJoin = fleet: join: leftRows: leftAliases:
    let
      joinKind = resolveKind join.kind;
      joinRows = getRows fleet joinKind;

      # The ON condition tells us which field on the join table matches which field on the left
      # e.g., ON svc.server = s.name means: joinRow.server == leftRow.name
      matchRows = leftRow: leftAlias:
        let
          # Build alias map for value resolution
          rowAliases = leftAlias // lib.optionalAttrs (join.alias != null) {
            ${join.alias} = leftRow; # placeholder, will be replaced per join row
          };

          matching = lib.filterAttrs (_: joinRow:
            let
              fullAliases = rowAliases // lib.optionalAttrs (join.alias != null) {
                ${join.alias} = joinRow;
              };
              lv = resolveValue fullAliases leftRow join.on.left;
              rv = resolveValue fullAliases leftRow join.on.right;
            in
            lv == rv
          ) joinRows;
        in
        if matching == {} then
          if join.isLeft then
            # LEFT JOIN: include row with nulls for joined fields
            [ {
              row = leftRow;
              aliases = rowAliases // lib.optionalAttrs (join.alias != null) {
                ${join.alias} = {};
              };
            } ]
          else []
        else
          lib.mapAttrsToList (_: joinRow: {
            row = leftRow // joinRow;
            aliases = rowAliases // lib.optionalAttrs (join.alias != null) {
              ${join.alias} = joinRow;
            };
          }) matching;
    in
    builtins.concatMap (item:
      matchRows item.row item.aliases
    ) leftRows;

  # Project selected columns from a row
  projectRow = aliases: row: selectCols:
    if builtins.length selectCols == 1 && (builtins.head selectCols).column == "*" then
      row
    else
      lib.listToAttrs (map (col:
        let
          targetRow =
            if col.table != null && aliases ? ${col.table} then
              aliases.${col.table}
            else row;
          val = getField targetRow col.column;
        in
        { name = col.column; value = val; }
      ) selectCols);

  # Compare values for ORDER BY
  compareValues = a: b:
    if builtins.isString a && builtins.isString b then a < b
    else if builtins.isInt a && builtins.isInt b then a < b
    else builtins.toJSON a < builtins.toJSON b;

  # Main query function: fleet → SQL string → result set
  query = fleet: sqlString:
    let
      parseSql = (import ./sql.nix { inherit lib; }).parseSql;
      ast = parseSql sqlString;
    in
    evalQuery fleet ast;

  # Evaluate a parsed AST against fleet data
  evalQuery = fleet: ast:
    let
      # FROM clause
      fromKind = resolveKind ast.from.kind;
      fromRows = getRows fleet fromKind;
      fromAlias = ast.from.alias;

      # Build initial row set with alias tracking
      initialRows = lib.mapAttrsToList (_: row: {
        inherit row;
        aliases =
          lib.optionalAttrs (fromAlias != null) { ${fromAlias} = row; };
      }) fromRows;

      # Apply JOINs sequentially
      joinedRows = builtins.foldl' (rows: join:
        resolveJoin fleet join rows (builtins.head rows).aliases or {}
      ) initialRows ast.joins;

      # Apply WHERE filter
      filteredRows = builtins.filter (item:
        evalWhere item.aliases item.row ast.where
      ) joinedRows;

      # Project columns
      projectedRows = map (item:
        projectRow item.aliases item.row ast.select
      ) filteredRows;

      # ORDER BY
      orderedRows =
        if ast.orderBy == null then projectedRows
        else
          let
            colName = ast.orderBy.column;
          in
          builtins.sort (a: b: compareValues (a.${colName} or "") (b.${colName} or "")) projectedRows;

      # LIMIT
      limitedRows =
        if ast.limit == null then orderedRows
        else lib.take ast.limit orderedRows;
    in
    limitedRows;

in
{
  inherit query evalQuery evalWhere resolveKind getRows getField;
}
