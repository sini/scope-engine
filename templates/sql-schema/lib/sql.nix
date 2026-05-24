# SQL string parser — tokenizer + recursive descent parser.
#
# Supports: SELECT (columns, *), FROM (kind, alias), JOIN / LEFT JOIN (ON condition),
# WHERE (=, !=, <, >, <=, >=, LIKE, IN, IS NULL, IS NOT NULL, AND, OR), ORDER BY, LIMIT.
#
# Produces an AST attrset: { select, from, joins, where, orderBy, limit }.
{ lib }:
let
  # ── Tokenizer ──
  # Splits SQL string into a list of tokens.
  # Token types: keyword, ident, string, number, op, star, comma, lparen, rparen, dot
  keywords = [
    "SELECT" "FROM" "JOIN" "LEFT" "ON" "WHERE" "AND" "OR" "IN"
    "IS" "NOT" "NULL" "ORDER" "BY" "LIMIT" "AS" "LIKE" "TRUE" "FALSE"
  ];

  isKeyword = s: builtins.elem (lib.toUpper s) keywords;

  # Uppercase a single ASCII character
  toUpperChar = c:
    let
      lower = "abcdefghijklmnopqrstuvwxyz";
      upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      idx = lib.lists.findFirstIndex (x: x == c) null (lib.stringToCharacters lower);
    in
    if idx != null then builtins.elemAt (lib.stringToCharacters upper) idx else c;

  toUpper = s:
    lib.concatStrings (map toUpperChar (lib.stringToCharacters s));

  # Split input on whitespace, preserving quoted strings and operators
  tokenize = input:
    let
      chars = lib.stringToCharacters input;
      len = builtins.length chars;

      # State machine tokenizer
      go = pos: acc: currentToken: inString:
        if pos >= len then
          if currentToken != "" then acc ++ [ currentToken ]
          else acc
        else
          let
            c = builtins.elemAt chars pos;
          in
          if inString then
            if c == "'" then
              # End of string literal — wrap in quotes to distinguish from identifiers
              go (pos + 1) (acc ++ [ "'${currentToken}'" ]) "" false
            else
              go (pos + 1) acc (currentToken + c) true
          else if c == "'" then
            # Start of string literal
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken ]) "" true
            else
              go (pos + 1) acc "" true
          else if c == " " || c == "\t" || c == "\n" || c == "\r" then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken ]) "" false
            else
              go (pos + 1) acc "" false
          else if c == "," then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "," ]) "" false
            else
              go (pos + 1) (acc ++ [ "," ]) "" false
          else if c == "(" then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "(" ]) "" false
            else
              go (pos + 1) (acc ++ [ "(" ]) "" false
          else if c == ")" then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken ")" ]) "" false
            else
              go (pos + 1) (acc ++ [ ")" ]) "" false
          else if c == "." then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "." ]) "" false
            else
              go (pos + 1) (acc ++ [ "." ]) "" false
          else if c == "*" then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "*" ]) "" false
            else
              go (pos + 1) (acc ++ [ "*" ]) "" false
          else if c == "=" then
            if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "=" ]) "" false
            else
              go (pos + 1) (acc ++ [ "=" ]) "" false
          else if c == "!" then
            # Look ahead for !=
            if pos + 1 < len && builtins.elemAt chars (pos + 1) == "=" then
              if currentToken != "" then
                go (pos + 2) (acc ++ [ currentToken "!=" ]) "" false
              else
                go (pos + 2) (acc ++ [ "!=" ]) "" false
            else
              go (pos + 1) acc (currentToken + c) false
          else if c == "<" then
            # Look ahead for <=
            if pos + 1 < len && builtins.elemAt chars (pos + 1) == "=" then
              if currentToken != "" then
                go (pos + 2) (acc ++ [ currentToken "<=" ]) "" false
              else
                go (pos + 2) (acc ++ [ "<=" ]) "" false
            else if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken "<" ]) "" false
            else
              go (pos + 1) (acc ++ [ "<" ]) "" false
          else if c == ">" then
            # Look ahead for >=
            if pos + 1 < len && builtins.elemAt chars (pos + 1) == "=" then
              if currentToken != "" then
                go (pos + 2) (acc ++ [ currentToken ">=" ]) "" false
              else
                go (pos + 2) (acc ++ [ ">=" ]) "" false
            else if currentToken != "" then
              go (pos + 1) (acc ++ [ currentToken ">" ]) "" false
            else
              go (pos + 1) (acc ++ [ ">" ]) "" false
          else
            go (pos + 1) acc (currentToken + c) false;
    in
    go 0 [] "" false;

  # Classify a token
  classifyToken = tok:
    if tok == "*" then { type = "star"; value = "*"; }
    else if tok == "," then { type = "comma"; value = ","; }
    else if tok == "(" then { type = "lparen"; value = "("; }
    else if tok == ")" then { type = "rparen"; value = ")"; }
    else if tok == "." then { type = "dot"; value = "."; }
    else if tok == "=" then { type = "op"; value = "="; }
    else if tok == "!=" then { type = "op"; value = "!="; }
    else if tok == "<" then { type = "op"; value = "<"; }
    else if tok == ">" then { type = "op"; value = ">"; }
    else if tok == "<=" then { type = "op"; value = "<="; }
    else if tok == ">=" then { type = "op"; value = ">="; }
    else if lib.hasPrefix "'" tok then { type = "string"; value = builtins.substring 1 (builtins.stringLength tok - 2) tok; }
    else if builtins.match "[0-9]+" tok != null then { type = "number"; value = lib.strings.toInt tok; }
    else if isKeyword tok then { type = "keyword"; value = toUpper tok; }
    else { type = "ident"; value = tok; };

  # ── Parser ──
  # Recursive descent parser over classified token list.
  # Returns { result = <ast>; rest = <remaining tokens>; }

  peek = tokens: if tokens == [] then null else builtins.head tokens;
  peekVal = tokens: if tokens == [] then null else (builtins.head tokens).value;
  advance = tokens: if tokens == [] then [] else builtins.tail tokens;
  consume = expected: tokens:
    let t = peek tokens; in
    if t == null then throw "sql-parser: unexpected end of input, expected ${expected}"
    else if t.value == expected then advance tokens
    else throw "sql-parser: expected '${expected}', got '${t.value}'";

  # Parse a column reference: may be "col", "alias.col", or "*"
  parseColumnRef = tokens:
    let t = peek tokens; in
    if t == null then throw "sql-parser: expected column reference"
    else if t.type == "star" then {
      result = { column = "*"; table = null; };
      rest = advance tokens;
    }
    else if t.type == "ident" then
      let
        rest1 = advance tokens;
        next = peek rest1;
      in
      if next != null && next.type == "dot" then
        let
          rest2 = advance rest1;
          col = peek rest2;
        in
        if col != null && (col.type == "ident" || col.type == "star") then {
          result = { table = t.value; column = col.value; };
          rest = advance rest2;
        }
        else throw "sql-parser: expected column name after '.'"
      else {
        result = { table = null; column = t.value; };
        rest = rest1;
      }
    else throw "sql-parser: expected column reference, got ${t.type}";

  # Parse SELECT column list
  parseSelectColumns = tokens:
    let
      t = peek tokens;
    in
    if t != null && t.type == "star" then {
      result = [ { column = "*"; table = null; } ];
      rest = advance tokens;
    }
    else
      let
        parseOne = toks:
          let ref = parseColumnRef toks;
          in ref;

        parseMore = acc: toks:
          let next = peek toks; in
          if next != null && next.type == "comma" then
            let
              ref = parseOne (advance toks);
            in
            parseMore (acc ++ [ ref.result ]) ref.rest
          else { result = acc; rest = toks; };

        first = parseOne tokens;
      in
      parseMore [ first.result ] first.rest;

  # Parse FROM clause: kind [alias]
  parseFrom = tokens:
    let t = peek tokens; in
    if t == null then throw "sql-parser: expected table name in FROM clause"
    else
      let
        rest1 = advance tokens;
        next = peek rest1;
        # Check if next token is an alias (ident that isn't a keyword for JOIN/WHERE/ORDER/LIMIT)
        isAlias = next != null && next.type == "ident" && !(builtins.elem (toUpper next.value) [
          "JOIN" "LEFT" "WHERE" "ORDER" "LIMIT" "ON" "AND" "OR" "INNER" "OUTER" "GROUP" "HAVING"
        ]);
      in
      if isAlias then {
        result = { kind = t.value; alias = next.value; };
        rest = advance rest1;
      }
      else {
        result = { kind = t.value; alias = null; };
        rest = rest1;
      };

  # Parse JOIN ... ON condition
  parseJoin = isLeft: tokens:
    let
      from = parseFrom tokens;
      rest1 = consume "ON" from.rest;
      # Parse ON condition: left = right
      leftRef = parseColumnRef rest1;
      rest2 = consume "=" leftRef.rest;
      rightRef = parseColumnRef rest2;
    in
    {
      result = {
        inherit isLeft;
        inherit (from.result) kind alias;
        on = {
          left = leftRef.result;
          right = rightRef.result;
        };
      };
      rest = rightRef.rest;
    };

  # Parse all JOINs
  parseJoins = tokens:
    let
      go = acc: toks:
        let t = peek toks; in
        if t == null then { result = acc; rest = toks; }
        else if t.value == "JOIN" then
          let j = parseJoin false (advance toks);
          in go (acc ++ [ j.result ]) j.rest
        else if t.value == "LEFT" then
          let
            rest1 = advance toks;
            next = peek rest1;
          in
          if next != null && next.value == "JOIN" then
            let j = parseJoin true (advance rest1);
            in go (acc ++ [ j.result ]) j.rest
          else { result = acc; rest = toks; }
        else { result = acc; rest = toks; };
    in
    go [] tokens;

  # Parse a WHERE expression (with AND/OR, comparison operators, IN, IS NULL)
  parseWhere = tokens:
    let
      # Parse a primary expression (comparison, IN, IS NULL/NOT NULL, parenthesized)
      parsePrimary = toks:
        let t = peek toks; in
        if t == null then throw "sql-parser: expected WHERE expression"
        else if t.type == "lparen" then
          let
            inner = parseOr (advance toks);
            rest = consume ")" inner.rest;
          in { inherit (inner) result; rest = rest; }
        else
          let
            left = parseColumnRef toks;
            op = peek left.rest;
          in
          if op == null then throw "sql-parser: expected operator in WHERE clause"
          # IS NULL / IS NOT NULL
          else if op.value == "IS" then
            let
              rest1 = advance left.rest;
              next = peek rest1;
            in
            if next != null && next.value == "NOT" then
              let rest2 = consume "NULL" (advance rest1);
              in { result = { op = "IS NOT NULL"; left = left.result; }; rest = rest2; }
            else
              let rest2 = consume "NULL" rest1;
              in { result = { op = "IS NULL"; left = left.result; }; rest = rest2; }
          # IN (...)
          else if op.value == "IN" then
            let
              rest1 = consume "(" (advance left.rest);
              parseList = acc: tks:
                let
                  item = peek tks;
                in
                if item == null then throw "sql-parser: unexpected end in IN list"
                else if item.type == "rparen" then { result = acc; rest = advance tks; }
                else if item.type == "comma" then parseList acc (advance tks)
                else
                  let
                    val = if item.type == "string" then item.value
                          else if item.type == "number" then item.value
                          else item.value;
                  in
                  parseList (acc ++ [ val ]) (advance tks);
              list = parseList [] rest1;
            in {
              result = { op = "IN"; left = left.result; right = list.result; };
              rest = list.rest;
            }
          # LIKE 'pattern'
          else if op.value == "LIKE" then
            let
              rest1 = advance left.rest;
              pattern = peek rest1;
            in
            if pattern == null then throw "sql-parser: expected pattern after LIKE"
            else {
              result = { op = "LIKE"; left = left.result; right = pattern.value; };
              rest = advance rest1;
            }
          # =, !=, <, >, <=, >=
          else if op.type == "op" then
            let
              rest1 = advance left.rest;
              right = peek rest1;
            in
            if right == null then throw "sql-parser: expected value after operator"
            else if right.type == "string" then {
              result = { op = op.value; left = left.result; right = right.value; };
              rest = advance rest1;
            }
            else if right.type == "number" then {
              result = { op = op.value; left = left.result; right = right.value; };
              rest = advance rest1;
            }
            else if right.type == "keyword" && (right.value == "TRUE" || right.value == "FALSE") then {
              result = { op = op.value; left = left.result; right = right.value == "TRUE"; };
              rest = advance rest1;
            }
            else
              # Right side is a column ref
              let rRef = parseColumnRef rest1;
              in { result = { op = op.value; left = left.result; right = rRef.result; }; rest = rRef.rest; }
          else throw "sql-parser: unexpected operator '${op.value}' in WHERE clause";

      # Parse AND chains
      parseAnd = toks:
        let
          left = parsePrimary toks;
          go = acc: tks:
            let t = peek tks; in
            if t != null && t.value == "AND" then
              let right = parsePrimary (advance tks);
              in go { op = "AND"; left = acc; right = right.result; } right.rest
            else { result = acc; rest = tks; };
        in
        go left.result left.rest;

      # Parse OR chains
      parseOr = toks:
        let
          left = parseAnd toks;
          go = acc: tks:
            let t = peek tks; in
            if t != null && t.value == "OR" then
              let right = parseAnd (advance tks);
              in go { op = "OR"; left = acc; right = right.result; } right.rest
            else { result = acc; rest = tks; };
        in
        go left.result left.rest;
    in
    parseOr tokens;

  # Parse ORDER BY
  parseOrderBy = tokens:
    let t = peek tokens; in
    if t != null && t.value == "ORDER" then
      let
        rest1 = consume "BY" (advance tokens);
        col = parseColumnRef rest1;
      in
      { result = col.result; rest = col.rest; }
    else
      { result = null; rest = tokens; };

  # Parse LIMIT
  parseLimit = tokens:
    let t = peek tokens; in
    if t != null && t.value == "LIMIT" then
      let
        rest1 = advance tokens;
        num = peek rest1;
      in
      if num != null && num.type == "number" then
        { result = num.value; rest = advance rest1; }
      else throw "sql-parser: expected number after LIMIT"
    else
      { result = null; rest = tokens; };

  # Main parser: SQL string → AST
  parseSql = input:
    let
      rawTokens = tokenize input;
      tokens = map classifyToken rawTokens;

      # SELECT
      rest1 = consume "SELECT" tokens;
      selectResult = parseSelectColumns rest1;

      # FROM
      rest2 = consume "FROM" selectResult.rest;
      fromResult = parseFrom rest2;

      # JOINs
      joinResult = parseJoins fromResult.rest;

      # WHERE (optional)
      whereTokens = joinResult.rest;
      hasWhere = peek whereTokens != null && (peek whereTokens).value == "WHERE";
      whereResult =
        if hasWhere then parseWhere (advance whereTokens)
        else { result = null; rest = whereTokens; };

      # ORDER BY (optional)
      orderResult = parseOrderBy whereResult.rest;

      # LIMIT (optional)
      limitResult = parseLimit orderResult.rest;
    in
    {
      select = selectResult.result;
      from = fromResult.result;
      joins = joinResult.result;
      where = whereResult.result;
      orderBy = orderResult.result;
      limit = limitResult.result;
    };

in
{
  inherit parseSql tokenize classifyToken;
}
