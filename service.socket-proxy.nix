{ config, ... }:
{
  # Read-only, filtered view of the podman API for Traefik's docker provider.
  # Traefik never sees the raw socket (which is root-equivalent); it only talks
  # to tcp://127.0.0.1:2375, which the proxy restricts to the GET endpoints
  # needed for service discovery (containers, networks, events, ping, version).
  virtualisation.oci-containers.containers.socket-proxy = {
    image = "ghcr.io/tecnativa/docker-socket-proxy:0.3.0";
    autoStart = true;

    # Only listen on loopback — the host-local Traefik service reaches it here.
    ports = [ "127.0.0.1:2375:2375" ];

    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
    ];

    environment = {
      CONTAINERS = "1";
      NETWORKS = "1";
      # EVENTS / PING / VERSION default to 1 in the image; POST stays 0 (read-only).
      POST = "0";
    };
  };

  # The proxy needs the podman API socket up first. (Ordering against the shared
  # networks is handled centrally in service.podman-networks.nix, keyed off the
  # module's own serviceName — no hardcoded unit name here.)
  systemd.services.${config.virtualisation.oci-containers.containers.socket-proxy.serviceName} = {
    after = [ "podman.socket" ];
    requires = [ "podman.socket" ];
  };
}
