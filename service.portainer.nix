{ vars, ... }:
{
  virtualisation.oci-containers.containers.portainer = {
    image = "portainer/portainer-ce:2.33.6-alpine";
    autoStart = true;
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock"
      "${vars.appDataDir}/portainer:/data"
    ];
    extraOptions = [
      "--privileged" # Allows Portainer proper host/socket access under Podman
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
    after = [ "podman-networks.service" ];
    requires = [ "podman-networks.service" ];
  };
}
