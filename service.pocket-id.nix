{ config, pkgs, ...}: {

  agenix.secrets = {
    "secret.pocket-id.encryption-key" = ./secret.pocket-id.encryption-key.age;
  };

  services.pocket-id = {
    enable = true;
    credentials = {
      ENCRYPTION_KEY = config.age.secrets."secret.pocket-id.encryption-key".path;
    };
    settings = {
      APP_URL = "https://id.thiccdata.io";
      TRUST_PROXY = true;
      HOST = "127.0.0.1";
    };
  };
}
