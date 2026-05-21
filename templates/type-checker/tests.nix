# Type checker tests.
{ engine, lib, result }:
{
  # ─── Structural subtyping (van Antwerpen 2018 §2.3) ────────────

  point2d-subtype-of-point3d = engine.subtypeOf { } result "Point2D" "Point3D";
  point3d-not-subtype-of-point2d = engine.subtypeOf { } result "Point3D" "Point2D";
  color-not-subtype-of-point3d = engine.subtypeOf { } result "Color" "Point3D";
  point2d-value-subtype = engine.subtypeOf { eq = _k: a: b: a == b; } result "Point2D" "Point3D";

  # ─── Record extension via R edges (van Antwerpen 2018 Fig. 4) ──

  named-point-fields =
    let
      fields = result.evaluated.NamedPoint.get "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  named-point-field-count = result.evaluated.NamedPoint.get "fieldCount";

  named-point-name-type =
    let
      fields = result.evaluated.NamedPoint.get "fields";
    in
    fields.name;

  # ─── Class inheritance via E edges (Neron 2015 §3, Fig. 16) ────

  circle-fields =
    let
      fields = result.evaluated.Circle.get "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  rect-fields =
    let
      fields = result.evaluated.Rect.get "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  shape-fields = builtins.attrNames (result.evaluated.Shape.get "fields");

  circle-has-shape-fields =
    let
      shapeFields = result.evaluated.Shape.get "fields";
      circleFields = result.evaluated.Circle.get "fields";
    in
    builtins.all (k: circleFields ? ${k}) (builtins.attrNames shapeFields);

  # ─── Scoped relations: type vs value namespaces ─────────────────

  type-lookup-num = result.evaluated.root.get "typeKind" "Num";
  type-lookup-circle = result.evaluated.root.get "typeKind" "Circle";
  type-lookup-unknown = result.evaluated.root.get "typeKind" "Nonexistent";
  env-bindings = result.nodes.env.rels.bindings;

  # ─── HOAG synthesis: generic instantiation (Vogt 1989) ──────────

  pair-exists = result.nodes ? "Pair<Num,String>";
  pair-fields = result.nodes."Pair<Num,String>".decls;
  pair-type = result.nodes."Pair<Num,String>".type;

  all-records = builtins.sort builtins.lessThan
    (builtins.attrNames (engine.nodesByType result "record"));

  # ─── Custom edge labels ─────────────────────────────────────────

  r-edges = engine.followEdge "R" result "NamedPoint";
  e-edges = engine.followEdge "E" result "Circle";
  no-e-on-record = engine.followEdge "E" result "Point2D";

  # ─── Ambiguity ──────────────────────────────────────────────────

  name-not-ambiguous = engine.ambiguous {
    dataFilter = n: n.decls.name or null;
  } result "NamedPoint";
}
