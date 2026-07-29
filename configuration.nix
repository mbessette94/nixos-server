{ config
, inputs
, pkgs
, vars
, ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  ## System
  networking.hostName = vars.hostName;

  ### Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  ### ZFS
  networking.hostId = vars.hostId;
  boot.supportedFilesystems = [ "zfs" ];
  # Both pools are declared under `fileSystems` below (with zfsutil), so they're
  # imported by the mount units — no need for boot.zfs.extraPools too.

  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "monthly";

  fileSystems."${vars.hddPool}" = {
    device = "thiccdata";
    fsType = "zfs";
    # optional flags: "zfsutil" is required if zfs property is mountpoint=/thiccdata
    options = [ "zfsutil" ];
  };

  fileSystems."${vars.ssdPool}" = {
    device = "thiccdata-ssd";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  systemd.tmpfiles.rules = [
    "d ${vars.ssdPool} 0750 captain captain - -"
    "d ${vars.hddPool} 0750 captain captain - -"
  ];

  ### Network hardware
  networking = {
    useDHCP = false;
    defaultGateway = vars.hosts.gateway;
    nameservers = [ vars.hosts.dns ];

    # 1. Host NIC -> Static IP for the NixOS host.
    interfaces.${vars.net.wanInterface} = {
      ipv4.addresses = [
        {
          address = vars.hosts.self;
          prefixLength = 24; # standard 255.255.255.0 netmask
        }
      ];
    };

    # 2. Second NIC -> Unmanaged by the host (reserved for Podman/Docker).
    # Leaving it empty prevents NixOS from assigning an IP or gateway,
    # but keeps the physical link layer active.
    interfaces.${vars.net.podmanInterface} = { };
  };

  ## Required secrets
  age.secrets = {
    "mbessette-password".file = ./secret.mbessette-password.age;
    "captain-password".file = ./secret.captain-password.age;
  };

  ## Base settings
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Required. The release this host was first provisioned on — leave pinned even
  # as nixpkgs advances, so stateful defaults (e.g. DB versions) don't shift.
  system.stateVersion = "26.05";

  ## Global packages
  programs.zsh.enable = true;
  environment.variables.EDITOR = "vim";
  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.${pkgs.system}.default

    vim
    git
    htop
    wget
    curl

    podman-tui # Terminal UI to inspect containers
    podman-compose # For multi-container deployments
    dive # Inspect container image layers
    home-manager
  ];

  ## Default users
  # Accounts are fully declarative (hashedPasswordFile), so disallow out-of-band
  # useradd/passwd drift — the config is the source of truth.
  users.mutableUsers = false;

  users.users.mbessette = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ]; # sudo — mbessette is the SSH-reachable admin
    hashedPasswordFile = config.age.secrets."mbessette-password".path;
    openssh.authorizedKeys.keys = [
      vars.mbessetteSshPubKey
    ];
  };

  users.users.captain = {
    isNormalUser = true;
    shell = pkgs.zsh;
    hashedPasswordFile = config.age.secrets."captain-password".path;
    extraGroups = [ "wheel" ];

    # Crucial for Rootless Podman UID mapping:
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];

    # Allow captain's background containers to auto-start at boot without logging in:
    autoSubUidGidRange = true;
    linger = true;
  };

  ## SSH
  services.openssh = {
    enable = true;
    ports = [ vars.ports.ssh ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ "mbessette" ];
    };
  };

  ## VSCode Server
  services.vscode-server.enable = true;

  ## Containerization
  virtualisation.containers.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # Create a `docker` alias for podman, so drop-in commands work

    # Expose the podman API socket at /run/podman/podman.sock. The socket-proxy
    # (service.socket-proxy.nix) mounts it read-only so Traefik can auto-discover
    # containers by label without ever touching the raw (root-equivalent) socket.
    dockerSocket.enable = true;

    # Required for containers under podman-compose to communicate
    defaultNetwork.settings.dns_enabled = true;
  };

  # (`systemd.user.startServices` is a home-manager option, not a NixOS one, and
  # errors on 26.05 — removed. oci-containers run as root system units regardless.)
  # (Unified cgroup v2 hierarchy is the default on modern systemd/26.05 — no
  # boot.kernelParams override needed.)

  ## END
}
