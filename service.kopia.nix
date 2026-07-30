{ config, pkgs, vars, ... }:
let
  dataDirectory = "/thiccdata-ssd/kopia";
in
{
  age.secrets.kopia-envfile = {
    file = ./secret.kopia.envfile.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  environment.systemPackages = [ pkgs.kopia ];

  users.users.kopia = {
    isSystemUser = true;
    group = "kopia";
    # dataDirectory is on ZFS and pre-exists; createHome=false so activation
    # doesn't try to recreate/chown-clobber the existing state.
    home = dataDirectory;
    createHome = false;
  };
  users.groups.kopia = {};

  # Adjust top-level ownership only (z, not Z -- do not recurse into existing
  # kopia state, which is already correctly owned by whatever previously ran
  # kopia there). captain admin group can read/write the config.
  systemd.tmpfiles.rules = [
    "z ${dataDirectory} 0770 kopia captain - -"
  ];

  systemd.services.kopia-server = {
    description = "Kopia Backup Server";

    wantedBy = [ "multi-user.target" ];
    wants = [ "agenix.service" ];
    after = [ "network.target" "agenix.service" ];

    environment = {
      HOME = dataDirectory;
    };

    serviceConfig = {
      Type = "simple";
      User = "kopia";
      Group = "kopia";
      WorkingDirectory = dataDirectory;

      EnvironmentFile = config.age.secrets.kopia-envfile.path;

      # Bind to 127.0.0.1 so it's only accessible via Traefik.
      # --config-file points at the pre-existing repository.config from the
      # prior system (default location is ~/.config/kopia/repository.config
      # per XDG, but this repo migrated in with everything under `config/`).
      ExecStart = ''
        ${pkgs.kopia}/bin/kopia server start \
          --config-file=${dataDirectory}/config/repository.config \
          --address=127.0.0.1:${toString vars.ports.kopia-ui} \
          --ui \
          --insecure \
          --disable-csrf-token-checks
      '';

      Restart = "always";
      RestartSec = "10s";

      ProtectSystem = "full";
      ProtectHome = true;
      ReadWritePaths = [ dataDirectory ];
    };
  };

  # NO firewall rule needed for 51515! Traefik handles external ports (80/443).
}
