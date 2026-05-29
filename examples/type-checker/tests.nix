# Type checker tests.
{
  genScope,
  lib,
  result,
}:
{
  # --- Structural subtyping (van Antwerpen 2018 §2.3) ------------

  point2d-subtype-of-point3d = genScope.subtypeOf { } result "Point2D" "Point3D";
  point3d-not-subtype-of-point2d = genScope.subtypeOf { } result "Point3D" "Point2D";
  color-not-subtype-of-point3d = genScope.subtypeOf { } result "Color" "Point3D";
  point2d-value-subtype = genScope.subtypeOf {
    eq =
      _k: a: b:
      a == b;
  } result "Point2D" "Point3D";

  # --- Record extension via R edges (van Antwerpen 2018 Fig. 4) --

  named-point-fields =
    let
      fields = result.get "NamedPoint" "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  named-point-field-count = result.get "NamedPoint" "fieldCount";

  named-point-name-type =
    let
      fields = result.get "NamedPoint" "fields";
    in
    fields.name;

  # --- Class inheritance via E edges (Neron 2015 §3, Fig. 16) ----

  circle-fields =
    let
      fields = result.get "Circle" "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  rect-fields =
    let
      fields = result.get "Rect" "fields";
    in
    builtins.sort builtins.lessThan (builtins.attrNames fields);

  shape-fields = builtins.attrNames (result.get "Shape" "fields");

  circle-has-shape-fields =
    let
      shapeFields = result.get "Shape" "fields";
      circleFields = result.get "Circle" "fields";
    in
    builtins.all (k: circleFields ? ${k}) (builtins.attrNames shapeFields);

  # --- Scoped relations: type vs value namespaces -----------------

  type-lookup-num = result.get "root" "typeKind" "Num";
  type-lookup-circle = result.get "root" "typeKind" "Circle";
  type-lookup-unknown = result.get "root" "typeKind" "Nonexistent";
  env-bindings = (result.node "env").decls.__bindings;

  # --- HOAG synthesis: generic instantiation (Vogt 1989) ----------

  pair-exists = result.allNodes ? "Pair<Num,String>";
  pair-fields = (result.node "Pair<Num,String>").decls;
  pair-type = (result.node "Pair<Num,String>").type;

  all-records = builtins.sort builtins.lessThan (
    builtins.attrNames (genScope.nodesByType result "record")
  );

  # --- Custom edge labels ----------------------------------------

  r-edges = genScope.followEdge "R" result "NamedPoint";
  e-edges = genScope.followEdge "E" result "Circle";
  no-e-on-record = genScope.followEdge "E" result "Point2D";

  # --- Ambiguity --------------------------------------------------

  name-not-ambiguous = genScope.ambiguous {
    dataFilter = n: n.decls.name or null;
  } result "NamedPoint";
}
