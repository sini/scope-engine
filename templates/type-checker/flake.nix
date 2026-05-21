{
  description = "Type checker: structural records and subtyping via scope graphs (van Antwerpen 2018)";

  inputs = {
    scope-engine.url = "github:sini/scope-engine";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { scope-engine, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      engine = scope-engine { inherit lib; };

      # ═══════════════════════════════════════════════════════════════
      # Structural type system with records (van Antwerpen 2018 §2.3)
      #
      # Record types are modeled as scopes. Field declarations are
      # the scope's decls. Record extension uses R (record) edges.
      # Structural subtyping: A <: B iff every field in B exists in A.
      #
      # Type language:
      #   Num, Bool, String                    — primitives
      #   { x: Num, y: Num }                   — record type (scope)
      #   { z: Num } extends { x: Num, y: Num} — record extension (R edge)
      #   (Num, Num) -> Bool                   — function type
      #
      # Program:
      #   type Point2D = { x: Num, y: Num }
      #   type Point3D = { x: Num, y: Num, z: Num }
      #   type Color   = { r: Num, g: Num, b: Num }
      #   type Named   = { name: String }
      #   type NamedPoint = Named extends Point2D  (R edge: NamedPoint → Point2D)
      #   type Pair<A,B> = { fst: A, snd: B }      (generic, HOAG-synthesized)
      #
      #   let distance: (Point2D, Point2D) -> Num
      #   let origin: Point2D = { x: 0, y: 0 }
      #   let p3: Point3D = { x: 1, y: 2, z: 3 }
      #   distance(p3, origin)  -- OK: Point3D <: Point2D
      #
      #   class Shape { area: () -> Num }
      #   class Circle extends Shape { radius: Num }
      #   class Rect extends Shape { width: Num, height: Num }
      # ═══════════════════════════════════════════════════════════════

      baseNodes = engine.buildNodes {
        parentGraph = engine.star "root" [
          "Point2D" "Point3D" "Color" "Named" "NamedPoint"
          "Shape" "Circle" "Rect"
          "env"
        ];
        edgeGraphs = {
          # R = record field extension (van Antwerpen 2018 Fig. 4, 5)
          R = engine.edge "NamedPoint" "Point2D";
          # E = class inheritance (Neron 2015 §3, Fig. 16)
          E = engine.overlays [
            (engine.edge "Circle" "Shape")
            (engine.edge "Rect" "Shape")
          ];
        };
        decls = {
          root = {};
          # Record types: fields as declarations
          "Point2D" = { x = "Num"; y = "Num"; };
          "Point3D" = { x = "Num"; y = "Num"; z = "Num"; };
          "Color" = { r = "Num"; g = "Num"; b = "Num"; };
          "Named" = { name = "String"; };
          # NamedPoint: own field (name) + R edge to Point2D (x, y)
          "NamedPoint" = { name = "String"; };
          # Class hierarchy
          "Shape" = { area = "() -> Num"; };
          "Circle" = { radius = "Num"; };
          "Rect" = { width = "Num"; height = "Num"; };
          # Value environment
          env = {};
        };
        types = {
          root = "root";
          "Point2D" = "record"; "Point3D" = "record"; "Color" = "record";
          "Named" = "record"; "NamedPoint" = "record";
          "Shape" = "class"; "Circle" = "class"; "Rect" = "class";
          env = "env";
        };
        relations = {
          # Type namespace: what kind of type each name represents
          root = {
            typeDecl = {
              "Point2D" = "record"; "Point3D" = "record"; "Color" = "record";
              "Named" = "record"; "NamedPoint" = "record";
              "Shape" = "class"; "Circle" = "class"; "Rect" = "class";
              "Num" = "primitive"; "Bool" = "primitive"; "String" = "primitive";
            };
          };
          # Value environment: variable bindings with their types
          env = {
            bindings = {
              origin = "Point2D"; p3 = "Point3D";
              distance = "(Point2D, Point2D) -> Num";
            };
          };
        };
      };

      # Collect all fields for a record/class, including inherited via R and E edges.
      allFields = self: id:
        let
          node = self.nodes.${id};
          local = node.decls;
          # Fields from record extension (R edges)
          rFields = lib.foldl' (acc: rid:
            engine.shadow acc (allFields self rid)
          ) {} (engine.followEdge "R" self id);
          # Fields from class inheritance (E edges)
          eFields = lib.foldl' (acc: eid:
            engine.shadow acc (allFields self eid)
          ) {} (engine.followEdge "E" self id);
        in
        engine.shadow local (engine.shadow rFields eFields);

      attributes = {
        # All fields including inherited ones
        fields = allFields;

        # Field count (synthesized, rolls up)
        fieldCount = self: id: builtins.length (builtins.attrNames (allFields self id));

        # Type lookup in root's type namespace (scoped relations)
        typeKind = engine.paramAttr (self: id: typeName:
          let root = self.nodes.root;
          in (root.rels.typeDecl or {}).${typeName} or "unknown"
        );
      };

      # HOAG synthesis: instantiate Pair<A,B> for Pair<Num, String>
      synthesize = self: {
        "Pair<Num,String>" = {
          id = "Pair<Num,String>";
          parent = "root";
          decls = { fst = "Num"; snd = "String"; };
          imports = []; childrenIds = [];
          type = "record";
          edgesByLabel = {}; rels = {};
        };
      };

      result = engine.eval { inherit baseNodes attributes synthesize; };

    in
    {
      # ─── Structural subtyping (van Antwerpen 2018 §2.3) ────────────

      # Point2D <: Point3D (2D fields are subset of 3D fields)
      tests.point2d-subtype-of-point3d =
        engine.subtypeOf {} result "Point2D" "Point3D";
        # → true: distance(p3, origin) is valid

      # Point3D is NOT <: Point2D (z field missing in 2D)
      tests.point3d-not-subtype-of-point2d =
        engine.subtypeOf {} result "Point3D" "Point2D";
        # → false

      # Color is NOT <: Point3D (different field names entirely)
      tests.color-not-subtype-of-point3d =
        engine.subtypeOf {} result "Color" "Point3D";
        # → false

      # Subtype with value equality: same types match
      tests.point2d-value-subtype =
        engine.subtypeOf { eq = _k: a: b: a == b; } result "Point2D" "Point3D";
        # → true (x="Num", y="Num" in both)

      # ─── Record extension via R edges (van Antwerpen 2018 Fig. 4) ──

      # NamedPoint extends Point2D: should have name + x + y
      tests.named-point-fields =
        let fields = result.evaluated."NamedPoint".get "fields";
        in builtins.sort builtins.lessThan (builtins.attrNames fields);
        # → [ "name" "x" "y" ]

      tests.named-point-field-count =
        result.evaluated."NamedPoint".get "fieldCount";
        # → 3

      # NamedPoint's name shadows Point2D's fields (R edge)
      tests.named-point-name-type =
        let fields = result.evaluated."NamedPoint".get "fields";
        in fields.name;
        # → "String"

      # ─── Class inheritance via E edges (Neron 2015 §3, Fig. 16) ────

      # Circle inherits from Shape: should have radius + area
      tests.circle-fields =
        let fields = result.evaluated."Circle".get "fields";
        in builtins.sort builtins.lessThan (builtins.attrNames fields);
        # → [ "area" "radius" ]

      # Rect inherits from Shape: should have width + height + area
      tests.rect-fields =
        let fields = result.evaluated."Rect".get "fields";
        in builtins.sort builtins.lessThan (builtins.attrNames fields);
        # → [ "area" "height" "width" ]

      # Shape itself has only area
      tests.shape-fields =
        builtins.attrNames (result.evaluated."Shape".get "fields");
        # → [ "area" ]

      # Circle <: Shape (Circle has all Shape fields)
      # Using allFields for structural comparison
      tests.circle-has-shape-fields =
        let
          shapeFields = result.evaluated."Shape".get "fields";
          circleFields = result.evaluated."Circle".get "fields";
        in builtins.all (k: circleFields ? ${k}) (builtins.attrNames shapeFields);
        # → true

      # ─── Scoped relations: type vs value namespaces ─────────────────

      tests.type-lookup-num =
        result.evaluated.root.get "typeKind" "Num";
        # → "primitive"

      tests.type-lookup-circle =
        result.evaluated.root.get "typeKind" "Circle";
        # → "class"

      tests.type-lookup-unknown =
        result.evaluated.root.get "typeKind" "Nonexistent";
        # → "unknown"

      # Value bindings in env
      tests.env-bindings =
        result.nodes.env.rels.bindings;
        # → { origin = "Point2D"; p3 = "Point3D"; distance = "..."; }

      # ─── HOAG synthesis: generic instantiation (Vogt 1989) ──────────

      # Pair<Num, String> was synthesized by HOAG
      tests.pair-exists =
        result.nodes ? "Pair<Num,String>";
        # → true

      tests.pair-fields =
        result.nodes."Pair<Num,String>".decls;
        # → { fst = "Num"; snd = "String"; }

      tests.pair-type =
        result.nodes."Pair<Num,String>".type;
        # → "record"

      # Typed query finds all record types including synthesized
      tests.all-records =
        builtins.sort builtins.lessThan
          (builtins.attrNames (engine.nodesByType result "record"));
        # → [ "Color" "Named" "NamedPoint" "Pair<Num,String>" "Point2D" "Point3D" ]

      # ─── Custom edge labels ─────────────────────────────────────────

      tests.r-edges =
        engine.followEdge "R" result "NamedPoint";
        # → [ "Point2D" ]

      tests.e-edges =
        engine.followEdge "E" result "Circle";
        # → [ "Shape" ]

      tests.no-e-on-record =
        engine.followEdge "E" result "Point2D";
        # → []

      # ─── Ambiguity: same field name in extension chain ──────────────

      # NamedPoint.name is unambiguous (only one source)
      tests.name-not-ambiguous =
        engine.ambiguous {
          dataFilter = n: n.decls.name or null;
        } result "NamedPoint";
        # → false
    };
}
