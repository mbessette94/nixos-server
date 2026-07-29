{ config, pkgs, vars, ... }:
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

    dataDir = "${vars.appDataDir}/pocket-id";

    environmentFile = pkgs.writeText "pocket-id.env" ''
      PORT=${toString vars.ports.pocket-id}
      HOST=127.0.0.1
    '';

    settings = {
      APP_URL = "https://id.${vars.domain}";
      TRUST_PROXY = true;
    };
  };
}
