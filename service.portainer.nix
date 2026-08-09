{ vars, ... }:
let
  dataDirectory = "${vars.appDataDir}/applications/portainer";
in
{
  virtualisation.oci-containers.containers.portainer = {
    image = "portainer/portainer-ce:2.33.6-alpine";
    autoStart = true;
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock"
      "${dataDirectory}:/data"
    ];
    extraOptions = [
      "--privileged" # Allows Portainer proper host/socket access under Podman
      # Traefik discovers backends via labels ONLY on the network named in
      # `traefik.docker.network` (public-net). Without this attach, Portainer
      # sits on the default `podman` network and Traefik 502s.
      "--network=public-net"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.routers.portainer.rule" = "Host(`portainer.${vars.domain}`)";
      "traefik.http.routers.portainer.entrypoints" = "websecure";
      "traefik.http.routers.portainer.tls.certresolver" = "myresolver";
      "traefik.http.routers.portainer.middlewares" = "internal-secure@file";
      "traefik.http.services.portainer.loadbalancer.server.port" = "9000";
    };
  };

  systemd.services.podman-portainer = {
    after = [ "podman-networks.service" "podman.socket" ];
    requires = [ "podman-networks.service" "podman.socket" ];
  };

  systemd.tmpfiles.rules = [
    "z ${dataDirectory} 0770 root captain - -"
  ];
}
