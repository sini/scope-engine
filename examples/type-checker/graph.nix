# Structural type system scope graph (van Antwerpen 2018 §2.3).
#
# Record types are modeled as scopes. Field declarations are the scope's decls.
# Record extension uses R (record) edges. Class inheritance uses E edges.
# Structural subtyping: A <: B iff every field in B exists in A.
#
# Type language:
#   Num, Bool, String                     — primitives
#   { x: Num, y: Num }                    — record type (scope)
#   { z: Num } extends { x: Num, y: Num } — record extension (R edge)
#   (Num, Num) -> Bool                    — function type
#
# Program:
#   type Point2D = { x: Num, y: Num }
#   type Point3D = { x: Num, y: Num, z: Num }
#   type Color   = { r: Num, g: Num, b: Num }
#   type Named   = { name: String }
#   type NamedPoint = Named extends Point2D
#   type Pair<A,B> = { fst: A, snd: B }       (generic, HOAG-synthesized)
#
#   class Shape  { area: () -> Num }
#   class Circle extends Shape { radius: Num }
#   class Rect   extends Shape { width: Num, height: Num }
{ engine }:
let
  baseNodes = engine.buildNodes {
    parentGraph = engine.star "root" [
      "Point2D"
      "Point3D"
      "Color"
      "Named"
      "NamedPoint"
      "Shape"
      "Circle"
      "Rect"
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
      root = { };
      "Point2D" = {
        x = "Num";
        y = "Num";
      };
      "Point3D" = {
        x = "Num";
        y = "Num";
        z = "Num";
      };
      Color = {
        r = "Num";
        g = "Num";
        b = "Num";
      };
      Named = {
        name = "String";
      };
      NamedPoint = {
        name = "String";
      };
      Shape = {
        area = "() -> Num";
      };
      Circle = {
        radius = "Num";
      };
      Rect = {
        width = "Num";
        height = "Num";
      };
      env = { };
    };
    types = {
      root = "root";
      "Point2D" = "record";
      "Point3D" = "record";
      Color = "record";
      Named = "record";
      NamedPoint = "record";
      Shape = "class";
      Circle = "class";
      Rect = "class";
      env = "env";
    };
    relations = {
      root = {
        typeDecl = {
          "Point2D" = "record";
          "Point3D" = "record";
          Color = "record";
          Named = "record";
          NamedPoint = "record";
          Shape = "class";
          Circle = "class";
          Rect = "class";
          Num = "primitive";
          Bool = "primitive";
          String = "primitive";
        };
      };
      env = {
        bindings = {
          origin = "Point2D";
          p3 = "Point3D";
          distance = "(Point2D, Point2D) -> Num";
        };
      };
    };
  };

  # HOAG synthesis: instantiate Pair<A,B> for Pair<Num, String> (Vogt 1989).
  synthesize = _self: {
    "Pair<Num,String>" = {
      id = "Pair<Num,String>";
      parent = "root";
      decls = {
        fst = "Num";
        snd = "String";
      };
      imports = [ ];
      childrenIds = [ ];
      type = "record";
      edgesByLabel = { };
      rels = { };
    };
  };
in
{
  inherit baseNodes synthesize;
}
