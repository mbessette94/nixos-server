{ config, lib, pkgs, vars, ... }:
let
  dataDirectory = "/thiccdata-ssd/kopia";

  # --- Declarative snapshot-policy example (opt-in, inert until filled in) ---
  # Recommended split from the storage-review pass (see plan history): back up
  # small/irreplaceable data (photos, nextcloud, git, DBs, control-plane config);
  # leave large/re-obtainable data (media, roms-archive, games, youtube) on the
  # local ZFS HDD RAID only -- RAID already protects against drive failure, and
  # Kopia's dedup engine gains little from ingesting multi-terabyte libraries.
  # Populate these lists and this unit will apply them idempotently on every
  # rebuild via `kopia policy set`. Left empty by default -- fill in deliberately.
  backupPaths = [
    # "/thiccdata/photos"
    # "/thiccdata-ssd/nextcloud-data"
    # "/thiccdata/nextcloud"
    # "/thiccdata-ssd/applications/git"
    # "/thiccdata/git-lfs"
    # "/thiccdata-ssd/applications/postgres"
    # "/thiccdata-ssd/db"
    # "/thiccdata/postgres"
    # "/thiccdata-ssd/infrastructure"
    # "/thiccdata-ssd/applications/portainer"
    # "/thiccdata-ssd/games/valheim"
  ];
  excludedPaths = [
    # "/thiccdata/media"
    # "/thiccdata/roms-archive"
    # "/thiccdata-ssd/games"
    # "/thiccdata/youtube"
    # "/thiccdata/roms"
  ];
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

  # Applies backupPaths/excludedPaths above via `kopia policy set`, idempotently,
  # on every rebuild + whenever kopia-server (re)starts. No-op while both lists
  # are empty. Reuses kopia-server's own repository config/credentials.
  systemd.services.kopia-policy-sync = lib.mkIf (backupPaths != [ ] || excludedPaths != [ ]) {
    description = "Apply declared Kopia snapshot policies";

    wantedBy = [ "multi-user.target" ];
    after = [ "kopia-server.service" ];
    wants = [ "kopia-server.service" ];

    environment = {
      HOME = dataDirectory;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "kopia";
      Group = "kopia";
      WorkingDirectory = dataDirectory;
      EnvironmentFile = config.age.secrets.kopia-envfile.path;
    };

    script =
      let
        kopiaArgs = "--config-file=${dataDirectory}/config/repository.config";
        setInclude = path: ''${pkgs.kopia}/bin/kopia policy set ${kopiaArgs} "${path}"'';
        setExclude = path: ''${pkgs.kopia}/bin/kopia policy set ${kopiaArgs} "${path}" --add-ignore="*"'';
      in
      lib.concatStringsSep "\n" (
        map setInclude backupPaths ++ map setExclude excludedPaths
      );
  };
}
