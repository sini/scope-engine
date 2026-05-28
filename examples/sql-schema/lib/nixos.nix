# NixOS configuration generator.
# Takes fleet data, queries infrastructure relationships via the SQL engine,
# and produces NixOS module configurations per server.
#
# This is the SQL equivalent of nest-traits' class.nixos builder:
# nest uses CSS selectors to pick config → host, this uses SQL queries.
{
  lib,
  bindLib,
}:
let
  # Find services running on a server
  serverServices =
    fleet: serverName:
    builtins.filter (svc: svc.server == serverName) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.service or { })
    );

  # Find exposed ports for a server (via its services)
  serverPorts =
    fleet: serverName:
    let
      svcNames = map (s: s.name or "") (serverServices fleet serverName);
    in
    builtins.filter (p: builtins.elem (p.service or "") svcNames && (p.expose or false)) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.port or { })
    );

  # Find interfaces for a server
  serverInterfaces =
    fleet: serverName:
    builtins.filter (i: (i.server or "") == serverName) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.interface or { })
    );

  # Find users assigned to a server
  serverUsers =
    fleet: serverName:
    builtins.filter (u: builtins.elem serverName (u.servers or [ ])) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.user or { })
    );

  # Find firewall rules for a server's subnet
  serverFirewallRules =
    fleet: serverName:
    let
      serverSubnet = (fleet.server.${serverName} or { }).subnet or "";
    in
    builtins.filter (r: (r.src-subnet or "") == serverSubnet || (r.dst-subnet or "") == serverSubnet) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.firewall-rule or { })
    );

  # Find certificates bound to a server
  serverCerts =
    fleet: serverName:
    builtins.filter (c: (c.server or null) == serverName) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.certificate or { })
    );

  # Find schedules on a server
  serverSchedules =
    fleet: serverName:
    builtins.filter (s: (s.server or "") == serverName && (s.enabled or false)) (
      lib.mapAttrsToList (name: v: v // { inherit name; }) (fleet.schedule or { })
    );

  # Look up a user's role permissions
  userPermissions =
    fleet: userName:
    let
      user = fleet.user.${userName} or { };
      roleName = user.ldap-role or "";
      role = fleet.ldap-role.${roleName} or { };
    in
    role.permissions or [ ];

  # Module function: takes fleet context, produces NixOS config attrset.
  # Separated from wrapping so gen-bind can inspect and bind args.
  serverModuleFn =
    {
      fleet,
      serverName,
      server,
      ...
    }:
    let
      interfaces = serverInterfaces fleet serverName;
      services = serverServices fleet serverName;
      ports = serverPorts fleet serverName;
      users = serverUsers fleet serverName;
      fwRules = serverFirewallRules fleet serverName;
      certs = serverCerts fleet serverName;
      schedules = serverSchedules fleet serverName;
    in
    {
      # Basic host identity
      networking.hostName = server.hostname;

      # Network interfaces
      networking.interfaces = builtins.listToAttrs (
        map (
          iface:
          let
            ifaceName = builtins.elemAt (lib.splitString "." iface.name) 1;
          in
          {
            name = ifaceName;
            value = {
              ipv4.addresses = [
                {
                  address = iface.ip;
                  prefixLength = 24;
                }
              ];
            };
          }
        ) interfaces
      );

      # Firewall: open exposed ports
      networking.firewall.allowedTCPPorts = map (p: p.number) (
        builtins.filter (p: p.protocol == "tcp") ports
      );
      networking.firewall.allowedUDPPorts = map (p: p.number) (
        builtins.filter (p: p.protocol == "udp") ports
      );

      # Users from LDAP
      users.users = builtins.listToAttrs (
        map (u: {
          name = u.name;
          value = {
            isNormalUser = true;
            uid = u.uid;
            shell = u.shell;
            openssh.authorizedKeys.keys = [ u.ssh-key ];
            extraGroups = lib.optional (builtins.elem "sudo" (userPermissions fleet u.name)) "wheel";
          };
        }) users
      );

      # Services
      services.openssh.enable = true;

      # Cron jobs from schedules
      services.cron.systemCronJobs = map (s: "${s.cron} root echo '${s.name} running'") schedules;

      # System tags as metadata
      environment.etc."server-tags".text = lib.concatStringsSep "\n" (server.tags or [ ]);

      # Environment label
      environment.etc."environment".text = server.environment;
    };

  # Build a wrapped NixOS module for a single server.
  # Returns gen-bind result: { module, wrapped, signature, advertisedArgs }
  buildServerModule =
    fleet: serverName:
    let
      server = fleet.server.${serverName};
    in
    bindLib.wrap {
      module = serverModuleFn;
      bindings = {
        inherit fleet serverName server;
      };
      contracts = {
        server = bindLib.contract.hasFields [
          "hostname"
          "os"
          "cores"
          "datacenter"
          "environment"
        ];
      };
      provenance = {
        server = {
          source = "fleet-registry";
          scope = "server=${serverName}";
        };
      };
    };

  # Evaluate a server module — calls the wrapped module to get the plain config attrset.
  # Backward-compatible replacement for code that expected buildServerModule to return a config.
  evalServerModule = fleet: serverName: (buildServerModule fleet serverName).module;

  # Build wrapped modules for all servers in the fleet.
  # Returns { serverName = gen-bind result; }
  buildAllModules = fleet: lib.mapAttrs (name: _: buildServerModule fleet name) (fleet.server or { });

  # Evaluate a server module directly — returns the config attrset for querying.
  evalServerConfig = fleet: serverName: evalServerModule fleet serverName;

  # Evaluate all servers, returning { serverName = config; }
  evalAllConfigs = fleet: lib.mapAttrs (name: _: evalServerConfig fleet name) (fleet.server or { });

  # ─── Post-eval query helpers ───

  # Which servers have a specific port open?
  serversWithPort =
    configs: port:
    lib.filterAttrs (_: cfg: builtins.elem port cfg.networking.firewall.allowedTCPPorts) configs;

  # Which servers have a specific user?
  serversWithUser =
    configs: userName: lib.filterAttrs (_: cfg: cfg.users.users ? ${userName}) configs;

  # Which servers have wheel (sudo) users?
  serversWithSudo =
    configs:
    lib.filterAttrs (
      _: cfg:
      builtins.any (u: builtins.elem "wheel" (u.extraGroups or [ ])) (builtins.attrValues cfg.users.users)
    ) configs;

  # Get all open ports across all servers
  allOpenPorts = configs: lib.mapAttrs (_: cfg: cfg.networking.firewall.allowedTCPPorts) configs;

  # Servers in a specific environment
  serversInEnv =
    configs: env: lib.filterAttrs (_: cfg: (cfg.environment.etc.environment.text or "") == env) configs;

  # Generic config path query: select servers where a config path has a specific value
  # Example: serversWhere configs ["networking" "firewall" "allowedTCPPorts"] (ports: builtins.elem 443 ports)
  serversWhere =
    configs: path: pred:
    lib.filterAttrs (
      _: cfg:
      let
        val = lib.attrByPath path null cfg;
      in
      val != null && pred val
    ) configs;

  # Select servers matching a config predicate, return { serverName = extractedValue; }
  # Example: selectFromConfigs configs (cfg: cfg.networking.hostName) (v: v != "")
  selectFromConfigs =
    configs: extract: pred:
    let
      extracted = lib.mapAttrs (
        _: cfg:
        let
          v = extract cfg;
        in
        if pred v then v else null
      ) configs;
    in
    lib.filterAttrs (_: v: v != null) extracted;

  # Flatten host configs into a queryable table for the SQL engine.
  # Each server becomes a row with columns extracted from the NixOS config.
  # Returns an attrset suitable as a fleet kind: { serverName = { col = val; ... }; }
  configsAsTable =
    configs:
    lib.mapAttrs (name: cfg: {
      inherit name;
      hostname = cfg.networking.hostName or name;
      open_tcp_ports = cfg.networking.firewall.allowedTCPPorts or [ ];
      open_udp_ports = cfg.networking.firewall.allowedUDPPorts or [ ];
      ssh_enabled = cfg.services.openssh.enable or false;
      nginx_enabled = cfg.services.nginx.enable or false;
      postgresql_enabled = cfg.services.postgresql.enable or false;
      sudo_enabled = cfg.security.sudo.enable or false;
      acme_enabled = cfg.security.acme.acceptTerms or false;
      monitoring_enabled = cfg.services.prometheus.exporters.node.enable or false;
      user_count = builtins.length (builtins.attrNames (cfg.users.users or { }));
      users = builtins.attrNames (cfg.users.users or { });
      cron_job_count = builtins.length (cfg.services.cron.systemCronJobs or [ ]);
      environment = cfg.environment.etc.environment.text or "";
      tags = cfg.environment.etc."server-tags".text or "";
    }) configs;

  # Query rendered NixOS configs with SQL strings.
  # Registers the flattened config table as "hosts" in the fleet, then runs the query.
  queryConfigs =
    queryFn: configs: sqlStr:
    let
      table = configsAsTable configs;
      # Create a synthetic fleet with just the hosts table
      syntheticFleet = {
        hosts = table;
      };
    in
    queryFn syntheticFleet sqlStr;
in
{
  inherit
    buildServerModule
    evalServerModule
    buildAllModules
    evalServerConfig
    evalAllConfigs
    serverServices
    serverPorts
    serverInterfaces
    serverUsers
    serverFirewallRules
    serverCerts
    serverSchedules
    ;

  # Post-eval query API
  queries = {
    inherit
      serversWithPort
      serversWithUser
      serversWithSudo
      allOpenPorts
      serversWhere
      selectFromConfigs
      configsAsTable
      queryConfigs
      serversInEnv
      ;
  };
}
