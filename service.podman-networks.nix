{ config, lib, pkgs, ... }:
{
  # Two shared podman networks that both Nix-declared containers and
  # Portainer-deployed containers attach to:
  #
  #   public-net   -> Traefik-facing (public). Traefik's docker provider
  #                   watches this network and routes to a container's IP
  #                   on it.
  #   private-net  -> --internal (no outbound internet). Backend-only
  #                   traffic, e.g. app <-> database. aardvark-dns resolves
  #                   container names within each network, so containers
  #                   reach each other by name.
  #                   (Not just "private" -- newer Podman versions reserve
  #                   that exact name as a built-in --network mode keyword,
  #                   which collides with a network of the same name.)
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

        path = [ pkgs.podman ];
        script = ''
          podman network exists public-net \
            || podman network create --subnet 172.22.0.0/24 public-net
          podman network exists private-net \
            || podman network create --internal --subnet 172.23.0.0/24 private-net
        '';
      };
    }

    # Make every oci-container wait for the shared networks to exist first.
    # The unit name is read from the module itself (`serviceName`, which defaults
    # to "<backend>-<name>") rather than hardcoded, so this keeps working if the
    # backend changes, a container is renamed, or new containers are added.
    (lib.mapAttrs'
      (name: container: lib.nameValuePair container.serviceName {
        after = [ "podman-networks.service" ];
        requires = [ "podman-networks.service" ];
      })
      config.virtualisation.oci-containers.containers)
  ];
}
