# RBAC scope graph.
#
# Role hierarchy:
#   viewer -> can: read
#   editor -> inherits viewer, can: read, write
#   admin  -> inherits editor, can: read, write, delete, manage
#   auditor -> inherits viewer, can: read, audit (parallel hierarchy)
#
# Users:
#   alice -> admin
#   bob   -> editor + auditor (multiple roles)
#   carol -> viewer
#   dave  -> editor, but DENIED delete on project-x
#
# Resources:
#   org/
#   +-- project-x/ (high sensitivity)
#   |   +-- doc-1
#   |   +-- doc-2
#   +-- project-y/ (low sensitivity)
#       +-- doc-3
{ engine, lib }:
{
  roots = engine.buildNodes {
    # Resource hierarchy (parent edges)
    parentGraph = engine.overlays [
      (engine.star "org" [
        "project-x"
        "project-y"
      ])
      (engine.star "project-x" [
        "doc-1"
        "doc-2"
      ])
      (engine.edge "doc-3" "project-y")
    ];
    edgeGraphs = {
      # R = role inheritance (Neron 2015 §3, Fig. 16)
      R = engine.overlays [
        (engine.edge "editor" "viewer")
        (engine.edge "admin" "editor")
        (engine.edge "auditor" "viewer")
      ];
      # A = role assignment (user -> role)
      A = engine.overlays [
        (engine.edge "alice" "admin")
        (engine.edge "bob" "editor")
        (engine.edge "bob" "auditor")
        (engine.edge "carol" "viewer")
        (engine.edge "dave" "editor")
      ];
      # D = deny override (user -> resource)
      D = engine.edge "dave" "project-x";
    };
    decls = {
      viewer = {
        read = true;
      };
      editor = {
        write = true;
      };
      admin = {
        delete = true;
        manage = true;
      };
      auditor = {
        audit = true;
      };
      alice = {
        email = "alice@corp.com";
      };
      bob = {
        email = "bob@corp.com";
      };
      carol = {
        email = "carol@corp.com";
      };
      dave = {
        email = "dave@corp.com";
        __deny = {
          "project-x" = [
            "delete"
            "manage"
          ];
        };
      };
      org = {
        name = "Acme Corp";
      };
      "project-x" = {
        name = "Project X";
        sensitivity = "high";
      };
      "project-y" = {
        name = "Project Y";
        sensitivity = "low";
      };
      "doc-1" = {
        title = "Design doc";
      };
      "doc-2" = {
        title = "API spec";
      };
      "doc-3" = {
        title = "Roadmap";
      };
    };
    types = {
      viewer = "role";
      editor = "role";
      admin = "role";
      auditor = "role";
      alice = "user";
      bob = "user";
      carol = "user";
      dave = "user";
      org = "resource";
      "project-x" = "resource";
      "project-y" = "resource";
      "doc-1" = "resource";
      "doc-2" = "resource";
      "doc-3" = "resource";
    };
  };
}
