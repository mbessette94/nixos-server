{ config, inputs, pkgs, vars, ...}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  ## System
  ### ZFS
  networking.hostId = "bf688067";
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "thiccdata" "thiccdata-ssd" ];

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
    defaultGateway = "192.168.1.1"; 
    nameservers = [ "192.168.1.200" ];

    # 1. PCIe 10Gb NIC -> Static IP for the NixOS Host
    interfaces.enp4s0 = { # Replace 'enp4s0' with actual 1G interface name
      ipv4.addresses = [{
        address = "192.168.1.45";
        prefixLength = 24; # standard 255.255.255.0 netmask
      }];
    };

    # 2. Onboard 1Gb NIC -> Unmanaged by Host (Used exclusively by Docker)
    # Leaving it empty prevents NixOS from assigning an IP or gateway, 
    # but keeps the physical link layer active for Docker.
    interfaces.enp5s0 = { }; # Replace 'enp5s0' with actual 10G interface name
  };


  ## Required secrets
  age.secrets = {
    "secret.mbessette-password" = ./secret.mbessette-password.age;
    "secret.captain-password" = ./secret.captain-password.age;
  };

  ## Base settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  ## Global packages
  environment.variables.EDITOR = "vim";
  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.${pkgs.system}.default

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
    extraGroups = [ "wheel" ]; # sudo — mbessette is the SSH-reachable admin
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
  services.openssh = {
    enable = true;
    ports = [ vars.ports.ssh ];
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

    # Expose the podman API socket at /run/podman/podman.sock. The socket-proxy
    # (service.socket-proxy.nix) mounts it read-only so Traefik can auto-discover
    # containers by label without ever touching the raw (root-equivalent) socket.
    dockerSocket.enable = true;

    # Required for containers under podman-compose to communicate
    defaultNetwork.settings.dns_enabled = true;
  };

  systemd.user.startServices = true;
  boot.kernelParams = [ "systemd.unified_cgroup_hierarchy=1" ];

  ## END
}
