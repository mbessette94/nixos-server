{ config, lib, pkgs, ... }:
{
  # Two shared podman networks that both Nix-declared containers and
  # Portainer-deployed containers attach to:
  #
  #   public-net   -> Traefik-facing. Traefik's docker provider watches this
  #                   network and routes to a container's IP on it.
  #   private-net  -> Backend traffic, e.g. app <-> database. aardvark-dns
  #                   resolves container names within each network, so
  #                   containers reach each other by name.
  #                   (Not just "private" -- newer Podman versions reserve
  #                   that exact name as a built-in --network mode keyword,
  #                   which collides with a network of the same name.)
  #                   NOTE: intentionally NOT --internal. Netavark 1.x + podman
  #                   5.x omit the netavark-table DNS-accept rule for internal
  #                   networks, silently dropping aardvark-dns queries from
  #                   containers on the internal bridge. Backend isolation
  #                   comes from not publishing ports (`ports = [...]`) on the
  #                   backend containers, not from --internal.
  #
  # A container that needs both (an app talking to a DB *and* exposed via
  # Traefik) simply attaches to both networks.
  systemd.services = lib.mkMerge [
    {
      podman-networks = {
        description = "Create shared podman networks (public-net, private-net)";
        wantedBy = [ "multi-user.target" ];
        after = [ "podman.service" "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        # IPv6 (ULA) subnets alongside the existing IPv4 ones so netavark sets
        # up IPv6 masquerade/forwarding for these networks the same way it
        # already does for IPv4 -- see configuration.nix for the matching
        # net.ipv6.conf.all.forwarding sysctl. NOTE: `--ignore` no-ops if a
        # network with this name already exists, so this does NOT
        # retroactively add IPv6 to networks created before this change --
        # see scripts/enable-podman-ipv6.sh for the one-time recreation step.
        path = [ pkgs.podman ];
        script = ''
          podman network create --ignore --subnet 172.22.0.0/24 --subnet fd00:22::/64 --ipv6 public-net
          podman network create --ignore --subnet 172.23.0.0/24 --subnet fd00:23::/64 --ipv6 private-net
        '';
      };
    }

    # Make every oci-container wait for the shared networks to exist first.
    # The unit name is read from the module itself (`serviceName`, which defaults
    # to "<backend>-<name>") rather than hardcoded, so this keeps working if the
    # backend changes, a container is renamed, or new containers are added.
    # NOTE: restrictedPorts (firewall.nix) only governs host-level services --
    # it does not cover ports a container publishes itself (`ports = [...]`
    # on an oci-container). Podman's netavark backend manages those in its
    # own nftables table, independent of the OS firewall's posture.
    (lib.mapAttrs'
      (name: container: lib.nameValuePair container.serviceName {
        after = [ "podman-networks.service" ];
        requires = [ "podman-networks.service" ];
      })
      config.virtualisation.oci-containers.containers)
  ];
}
