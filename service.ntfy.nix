{ vars, ... }:
{
  # ntfy: push-notification server. Two access paths:
  #   * Browser / phone  -> https://${ntfyHost} via Traefik (public-net network, labels).
  #   * Host alerts       -> http://127.0.0.1:<ntfy port> on loopback, so the
  #                          OnFailure hook (service.notify.nix) can publish
  #                          WITHOUT depending on Traefik/DNS/TLS being healthy.
  virtualisation.oci-containers.containers.ntfy = {
    image = "docker.io/binwiederhier/ntfy:latest";
    cmd = [ "serve" ];
    autoStart = true;

    # Loopback-only publish endpoint for host-originated alerts.
    ports = [ "127.0.0.1:${toString vars.ports.ntfy}:80" ];

    # Reachable by Traefik on the shared public-net network (see service.podman-networks.nix).
    extraOptions = [ "--network=public-net" ];

    volumes = [
      "${vars.appDataDir}/ntfy:/var/cache/ntfy"
    ];

    environment = {
      NTFY_BASE_URL = "https://${vars.ntfyHost}";
      NTFY_BEHIND_PROXY = "true";
      NTFY_LISTEN_HTTP = ":80";
      NTFY_CACHE_FILE = "/var/cache/ntfy/cache.db";
      # No auth for v1: access is gated by network reachability (Traefik's
      # internal-secure whitelist + loopback-only publish). Enable ntfy tokens
      # later if you expose it publicly.
    };

    labels = {
      "traefik.enable" = "true";
      "traefik.http.routers.ntfy.rule" = "Host(`${vars.ntfyHost}`)";
      "traefik.http.routers.ntfy.entrypoints" = "websecure";
      "traefik.http.routers.ntfy.tls.certresolver" = "myresolver";
      # Internal/VPN-only for now. For push while off-network without a VPN,
      # switch this to base-secure@file and enable ntfy auth (tokens).
      "traefik.http.routers.ntfy.middlewares" = "internal-secure@file";
      "traefik.http.services.ntfy.loadbalancer.server.port" = "80";
    };
  };

  # Persist ntfy's cache/attachments across container restarts.
  systemd.tmpfiles.rules = [
    "d ${vars.appDataDir}/ntfy 0770 root captain - -"
  ];
}
