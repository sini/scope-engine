let
  at = builtins.elemAt;
  len = builtins.length;
  sub = builtins.substring;
  splitOn = pat: str: builtins.filter builtins.isString (builtins.split pat str);
  trim =
    s:
    let
      m = builtins.match " *(.*[^ ]) *" s;
    in
    if m == null then s else at m 0;

  parseCompound =
    str:
    if str == "" then
      [ ]
    else
      let
        c = sub 0 1 str;
        rest = sub 1 (-1) str;
        parseTok =
          type: m:
          [
            {
              __sel = type;
              name = at m 0;
            }
          ]
          ++ parseCompound (at m 1);
      in
      if c == "*" then
        [ { __sel = "star"; } ] ++ parseCompound rest
      else if c == "#" then
        parseTok "id" (builtins.match "#([a-zA-Z0-9_/-]+)(.*)" str)
      else if c == "." then
        parseTok "class" (builtins.match "\\.([a-zA-Z0-9_/-]+)(.*)" str)
      else if c == "[" then
        let
          attrParts = splitOn "]" rest;
          inner = at attrParts 0;
          after = if len attrParts > 1 then at attrParts 1 else "";
          eqParts = splitOn "=" inner;
        in
        (
          if len eqParts > 1 then
            [
              {
                __sel = "attr";
                key = at eqParts 0;
                val = at eqParts 1;
              }
            ]
          else
            [
              {
                __sel = "attrExists";
                key = inner;
              }
            ]
        )
        ++ parseCompound after
      else if c == ":" then
        let
          m = builtins.match ":([a-z-]+)\\((.*)\\)(.*)" str;
        in
        [
          {
            __sel = at m 0;
            selector = parseCssSel (at m 1);
          }
        ]
        ++ parseCompound (at m 2)
      else
        let
          m = builtins.match "([a-zA-Z0-9_/-]+)(.*)" str;
        in
        if m != null then
          [
            {
              __sel = "name";
              name = at m 0;
            }
          ]
          ++ parseCompound (at m 1)
        else
          [ ];

  parseCssSel =
    str:
    let
      buildChain =
        type: parentKey: childKey: parts:
        builtins.foldl' (acc: p: {
          __sel = type;
          ${parentKey} = acc;
          ${childKey} = parseCssSel (trim p);
        }) (parseCssSel (trim (builtins.head parts))) (builtins.tail parts);

      compound =
        let
          tokens = parseCompound str;
        in
        if len tokens == 0 then
          { __sel = "star"; }
        else if len tokens == 1 then
          builtins.head tokens
        else
          tokens;

      orParts = splitOn "," str;
      childParts = splitOn " > " str;
      descParts = splitOn " \\+" str;
    in
    if len orParts > 1 then
      {
        __sel = "or";
        selectors = map (p: parseCssSel (trim p)) orParts;
      }
    else if len childParts > 1 then
      buildChain "child" "parentSel" "childSel" childParts
    else if len descParts > 1 then
      buildChain "descendant" "ancestorSel" "descendantSel" descParts
    else
      compound;
in
{
  inherit parseCompound parseCssSel;
}
