# Group definitions (from nix-config/docs/ACL.md).
# groups.<name> = { scope, description, members }
{
  # Identity (kanidm)
  admins = {
    scope = "kanidm";
    description = "Full administrative access";
    members = [ ];
  };
  users = {
    scope = "kanidm";
    description = "Standard user access";
    members = [ "admins" ];
  };

  # System login gates (opt-in — not inherited from identity groups)
  system-access = {
    scope = "system";
    description = "Login access to all hosts";
    members = [ ];
  };
  workstation-access = {
    scope = "system";
    description = "Login access to workstations";
    members = [ "system-access" ];
  };
  server-access = {
    scope = "system";
    description = "Login access to servers";
    members = [ "system-access" ];
  };

  # Service access (kanidm oauth2)
  "grafana.access" = {
    scope = "kanidm";
    description = "Grafana login";
    members = [ "users" ];
  };
  "grafana.server-admins" = {
    scope = "kanidm";
    description = "Grafana server admin";
    members = [ "admins" ];
  };
  "media.access" = {
    scope = "kanidm";
    description = "Jellyfin access";
    members = [ "users" ];
  };

  # Unix system groups
  wheel = {
    scope = "unix";
    description = "Sudo access";
    members = [ ];
  };
  podman = {
    scope = "unix";
    description = "Container runtime";
    members = [ ];
  };
  libvirtd = {
    scope = "unix";
    description = "VM management";
    members = [ ];
  };
  audio = {
    scope = "unix";
    description = "Audio device access";
    members = [ ];
  };
  video = {
    scope = "unix";
    description = "Video device access";
    members = [ ];
  };
  render = {
    scope = "unix";
    description = "GPU render access";
    members = [ ];
  };
}
