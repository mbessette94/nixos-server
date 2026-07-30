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

  # NOTE: the upstream pocket-id module ships its own tmpfiles rule
  # (`d ${cfg.dataDir} 0755 pocket-id pocket-id`) -- no override needed here.
  # pocket-id v2 writes the DB, keys, and uploads under `${dataDir}/data/`,
  # not directly in dataDir. `SQLITE_DB_PATH` is asserted out of the settings
  # in v2 (see the module's v2 migration guide); relocate existing data into
  # the `data/` subdir rather than trying to redirect the app.
}
