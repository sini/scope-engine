# Host definitions.
# hosts.<host> = { environment, role, system-access-groups }
{
  cortex = {
    environment = "prod";
    role = "workstation";
    system-access-groups = [ "workstation-access" ];
  };
  blade = {
    environment = "prod";
    role = "workstation";
    system-access-groups = [ "workstation-access" ];
  };
  patch = {
    environment = "prod";
    role = "workstation";
    system-access-groups = [ "system-access" ];
  };
  axon-01 = {
    environment = "prod";
    role = "server";
    system-access-groups = [ "server-access" ];
  };
  dev-box = {
    environment = "dev";
    role = "dev";
    system-access-groups = [ "workstation-access" ];
  };
}
