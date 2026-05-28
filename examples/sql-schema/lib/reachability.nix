# Network reachability synthesis — materializes server-to-server connectivity.
#
# Intersects firewall rules with network topology to determine which servers
# can reach which other servers and on which ports.
{ lib }:
let
  synthesizeReachability =
    rawFleet:
    let
      servers = rawFleet.server or { };
      firewallRules = rawFleet.firewall-rule or { };
      allServerNames = builtins.attrNames servers;

      # All ordered server pairs (excluding self)
      serverPairs = builtins.concatMap (
        src: map (dst: { inherit src dst; }) (builtins.filter (d: d != src) allServerNames)
      ) allServerNames;
    in
    lib.listToAttrs (
      builtins.concatMap (
        { src, dst }:
        let
          srcSubnet = servers.${src}.subnet or "";
          dstSubnet = servers.${dst}.subnet or "";

          # Find firewall rules allowing traffic between these subnets
          allowedRules = lib.filterAttrs (
            _: r: r.action == "allow" && r.src-subnet == srcSubnet && r.dst-subnet == dstSubnet
          ) firewallRules;

          allowedPorts = lib.mapAttrsToList (_: r: r.port) allowedRules;
        in
        lib.optional (allowedRules != { }) {
          name = "${src}:${dst}";
          value = {
            src-server = src;
            dst-server = dst;
            path = [
              src
              dst
            ];
            inherit allowedPorts;
          };
        }
      ) serverPairs
    );
in
{
  inherit synthesizeReachability;
}
