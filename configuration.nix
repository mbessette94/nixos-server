{ config, inputs, pkgs, vars, ...}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  ## Required secrets
  age.secrets = {
    "secret.mbessette-password" = ./secret.mbessette-password.age;
    "secret.captain-password" = ./secret.captain-password.age;
  };

  ## Base settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  ## Global packages
  environment.variables.EDITOR = "vim";
  environment.systemPackages = [
    inputs.agenix.packages."${system}".default
  ];
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    wget
    curl

    podman-tui     # Terminal UI to inspect containers
    podman-compose # For multi-container deployments
    dive           # Inspect container image layers
  ];

  ## Default users
  users.users.mbessette = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets."secret.mbessette-password".path;
    openssh.authorizedKeys.keys = [
      vars.mbessetteSshPubKey
    ];
  };

  users.users.captain = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets."secret.captain-password".path;
    extraGroups = [ "wheel" ];

    # Crucial for Rootless Podman UID mapping:
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    
    # Allow captain's background containers to auto-start at boot without logging in:
    autoSubUidGidRange = true;
    lingering = true;
  };

  ## SSH
  service.openssh = {
    enable = true;
    ports = [ 2222 ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = "no";
      AllowUsers = [ "mbessette" ];
    };
  };

  ## Containerization
  virtualisation.containers.enable = true;
  
  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # Create a `docker` alias for podman, so drop-in commands work
    
    # Required for containers under podman-compose to communicate
    defaultNetwork.settings.dns_enabled = true;
  };
  systemd.tmpfiles.rules = [
    "d /mnt/storage/appdata 0750 captain captain - -"
  ];
  systemd.user.startServices = true;
  boot.kernelParams = [ "systemd.unified_cgroup_hierarchy=1" ];

  ## END
}
