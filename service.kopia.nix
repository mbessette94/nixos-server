{ pkgs, ... }:
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
    home = "/var/lib/kopia";
    createHome = true;
  };
  users.groups.kopia = {};

  systemd.services.kopia-server = {
    description = "Kopia Backup Server";
    after = [ "network.target" ];

    wantedBy = [ "multi-user.target" ];
    wants = [ "agenix.service" ];
    after = [ "agenix.service" ];

    environment = {
      HOME = "/var/lib/kopia";
    };

    serviceConfig = {
      Type = "simple";
      User = "kopia";
      Group = "kopia";
      WorkingDirectory = "/var/lib/kopia";

      EnvironmentFile = config.age.secrets.kopia-envfile.path;
      
      # Bind to 127.0.0.1 so it's only accessible via Traefik
      ExecStart = ''
        ${pkgs.kopia}/bin/kopia server start \
          --address=127.0.0.1:51515 \
          --ui \
          --insecure \
          --disable-csrf-token-checks
      '';

      Restart = "always";
      RestartSec = "10s";

      ProtectSystem = "full";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/kopia" ];
    };
  };

  # NO firewall rule needed for 51515! Traefik handles external ports (80/443).
}