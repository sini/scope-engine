# Module resolver tests.
{ engine, lib, result }:
{
  # ─── Resolution: D < I < P specificity (Neron 2015 Fig. 2) ─────

  direct-lookup = result.evaluated."Std.IO".get "lookup" "print";
  # → "io.print"

  import-lookup = result.evaluated.App.get "lookup" "concat";
  # → "string.concat"

  parent-inherit = result.evaluated."App.Sub".get "lookup" "main";
  # → "app.main"

  sub-import = result.evaluated."App.Sub".get "lookup" "print";
  # → "io.print"

  # Transitive imports: String imports Math, so App sees pi through chain.
  transitive-import = engine.query {
    dataFilter = n: n.decls.pi or null;
    transitiveImports = true;
  } result "App";
  # → 3

  # Non-transitive (default): App cannot see Math's pi.
  non-transitive = engine.query {
    dataFilter = n: n.decls.pi or null;
  } result "App";
  # → null

  # ─── Ambiguity detection (van Antwerpen 2018) ───────────────────

  not-ambiguous = engine.ambiguous {
    dataFilter = n: n.decls.concat or null;
  } result "Std.String";
  # → false

  shadow-no-ambiguity = engine.ambiguous {
    dataFilter = n: n.decls.format or null;
  } result "App.Sub";
  # → false

  # ─── Cyclic imports (Neron 2015 §2.4, rule X) ──────────────────

  cycle-safe-c1 = engine.query {
    dataFilter = n: n.decls.val or null;
  } result "Cycle1";
  # → "c1"

  cycle-safe-c2 = engine.query {
    dataFilter = n: n.decls.val or null;
  } result "Cycle2";
  # → "c2"

  cycle-all-reachable = builtins.sort builtins.lessThan (
    engine.queryAll {
      dataFilter = n: n.decls.val or null;
    } result "Cycle1"
  );
  # → [ "c1" "c2" ]

  # ─── Shadowing (Neron 2015 §5, Def. 1) ─────────────────────────

  visible-decls-app-sub =
    let
      decls = result.evaluated."App.Sub".get "visibleDecls";
    in
    {
      has-helper = decls ? helper;
      has-main = decls ? main;
      has-print = decls ? print;
      has-format = decls ? format;
    };

  # ─── Structural queries ─────────────────────────────────────────

  std-submodules = builtins.sort builtins.lessThan (engine.childrenIds result "Std");
  app-sub-ancestors = engine.ancestors result "App.Sub";
  module-count = result.evaluated.root.get "moduleCount";
  typed-modules = builtins.length (builtins.attrNames (engine.nodesByType result "module"));
}
