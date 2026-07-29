{ config, pkgs, vars, ... }:
let
  dataDirectory = "${vars.appDataDir}/applications/pocket-id";
in
{
  age.secrets."pocket-id.encryption-key" = {
    file = ./secret.pocket-id.encryption-key.age;
    owner = "pocket-id";
  };

  services.pocket-id = {
    enable = true;
    credentials = {
      ENCRYPTION_KEY = config.age.secrets."pocket-id.encryption-key".path;
    };

    dataDir = "${dataDirectory}";

    environmentFile = pkgs.writeText "pocket-id.env" ''
      PORT=${toString vars.ports.pocket-id}
      HOST=127.0.0.1
    '';

    settings = {
      APP_URL = "https://id.${vars.domain}";
      TRUST_PROXY = true;
    };
  };

  # pocket-id has no ZFS dataset of its own under /thiccdata-ssd/applications
  # (unlike git/plex/portainer/postgres); the service's namespaced ExecStart
  # fails hard if this doesn't exist. Owned by pocket-id + captain admin group.
  systemd.tmpfiles.rules = [
    "d ${config.services.pocket-id.dataDir} 0770 pocket-id captain - -"
  ];
}
