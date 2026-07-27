{ config, pkgs, vars, ...}: {

  age.secrets."secret.pocket-id.encryption-key".file = ./secret.pocket-id.encryption-key.age;

  services.pocket-id = {
    enable = true;
    credentials = {
      ENCRYPTION_KEY = config.age.secrets."secret.pocket-id.encryption-key".path;
    };

    environmentFile = pkgs.writeText "pocket-id.env" ''
      PORT=${toString vars.ports.pocket-id}
      HOST=127.0.0.1
    '';

    settings = {
      APP_URL = "https://id.thiccdata.io";
      TRUST_PROXY = true;
    };
  };
}
