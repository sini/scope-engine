# Environment access bindings.
# environments.<env>.access = { user → [group] }
{
  prod = {
    access = {
      sini = [
        "admins"
        "system-access"
        "wheel"
        "podman"
        "libvirtd"
        "audio"
        "video"
        "render"
      ];
      shuo = [
        "users"
        "workstation-access"
        "wheel"
        "podman"
        "audio"
        "video"
        "render"
      ];
      will = [
        "users"
        "workstation-access"
        "wheel"
        "podman"
        "audio"
        "video"
        "render"
      ];
      json = [ "admins" ];
      hugs = [
        "users"
        "grafana.server-admins"
      ];
      greco = [ "users" ];
    };
    system-access-groups = [ "system-access" ];
  };
  dev = {
    access = {
      sini = [
        "admins"
        "system-access"
        "wheel"
      ];
    };
    system-access-groups = [ "system-access" ];
  };
}
