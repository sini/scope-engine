{
  lib,
  engine,
  sql,
  schemaLib,
  graphLib,
  genLib,
}:
{
  smoke = {
    test-fleet-loads = {
      expr = sql.fleet != null;
      expected = true;
    };
    test-fleet-has-servers = {
      expr = builtins.attrNames sql.fleet.server;
      expected = [ "api-1" "db-1" "web-1" "web-2" ];
    };
    test-fleet-has-all-kinds = {
      expr = builtins.sort builtins.lessThan (builtins.attrNames sql.fleet);
      expected = [
        "access-policy"
        "backend"
        "certificate"
        "datacenter"
        "dns-record"
        "domain"
        "environment"
        "firewall-rule"
        "interface"
        "ldap-group"
        "ldap-role"
        "loadbalancer"
        "network"
        "port"
        "schedule"
        "server"
        "service"
        "service-dependency"
        "subnet"
        "user"
        "vlan"
      ];
    };
  };
}
