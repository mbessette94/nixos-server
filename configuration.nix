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

  # Static timezone -- this box doesn't move, so no need for localtimed's
  # geolocation-driven timezone (which requires GeoClue2 + location services
  # and is intended for laptops). Change the value to your local zone; see
  # `timedatectl list-timezones` for options. NTP time sync is handled by
  # systemd-timesyncd, which NixOS enables by default.
  time.timeZone = "America/New_York";

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

  # Pool-root mountpoints -- 0755 so every service user (pocket-id, traefik, etc.)
  # can traverse into its own dir underneath. Per-app dirs still enforce their own
  # captain-group perms (0770).
  #
  # Owner is root, NOT captain: systemd-tmpfiles refuses to create/adjust any path
  # that requires walking through a directory owned by a non-root user whose child
  # has a different owner ("Detected unsafe path transition" -- protects against a
  # non-root owner swapping a subdirectory for a symlink before root operates on
  # it). With captain as owner here, every rule reaching into a root-owned (or
  # per-service-user-owned) child -- applications/, infrastructure/, portainer,
  # traefik, even kopia's own mode -- was silently skipped. Root-owned ancestors
  # are implicitly trusted, so this fixes the whole tree at once; captain still
  # gets read/traverse via the group bit, same as before.
  systemd.tmpfiles.rules = [
    "d ${vars.ssdPool} 0755 root captain - -"
    "d ${vars.hddPool} 0755 root captain - -"
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

  # IPv4 forwarding is enabled implicitly (podman/virtualisation modules need
  # it for container networking). IPv6 forwarding is NOT enabled by default
  # and was never turned on to match -- despite this host having real,
  # globally-routable IPv6 (SLAAC) on both NICs. Without this, any container
  # whose app resolves a dual-stack external host and attempts the AAAA/IPv6
  # address first gets an immediate "Network unreachable" (see
  # service.podman-networks.nix for the matching podman-network-side fix).
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

  ## Required secrets
  age.secrets = {
    "mbessette-password".file = ./secret.mbessette-password.age;
    "captain-password".file = ./secret.captain-password.age;
    "captain-u2f-keys".file = ./secret.captain-u2f-keys.age;
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
    systemctl-tui
    jq
    dig
  ];

  # Git refuses to operate on a repo it doesn't own (CVE-2022-24765 mitigation),
  # even when the non-owning user has group write access -- and /nixos-server is
  # owned by mbessette but group-writable by captain (both run `nix-update`/
  # `home-update` out of it). System-wide (not per-user) so it works for both
  # accounts without needing matching personal git configs.
  environment.etc.gitconfig.text = ''
    [safe]
        directory = /nixos-server
  '';

  ## Default users
  # Accounts are fully declarative (hashedPasswordFile), so disallow out-of-band
  # useradd/passwd drift — the config is the source of truth.
  users.mutableUsers = false;

  # Shared admin group for service data dirs under /thiccdata-ssd/applications/*.
  # Each per-service tmpfiles rule sets owner=<service-user>, group=captain, so
  # captain + mbessette can read/write app data without root.
  users.groups.captain = { };

  users.users.mbessette = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "captain" ]; # sudo — mbessette is the SSH-reachable admin
    hashedPasswordFile = config.age.secrets."mbessette-password".path;
    openssh.authorizedKeys.keys = [
      vars.mbessetteSshPubKey
    ];
  };

  users.users.captain = {
    isNormalUser = true;
    shell = pkgs.zsh;
    hashedPasswordFile = config.age.secrets."captain-password".path;
    extraGroups = [ "wheel" "captain" ];

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

    # FIDO2-backed SSH keys for captain's two YubiKeys -- not used for sshd
    # login (captain is deliberately excluded from AllowUsers below), but
    # read by security.pam.sshAgentAuth so `su - captain` can authenticate
    # against a forwarded agent instead of a password. See variables.nix.
    openssh.authorizedKeys.keys = vars.captainYubikeySshPubKeys;
  };

  ## SSH
  services.openssh = {
    enable = true;
    ports = [ vars.ports.ssh ];
    # Don't let the openssh module blanket-open this port to the world --
    # firewall.nix's restrictedPorts already opens it, restricted to localCidr.
    openFirewall = false;
    settings = {
      AllowAgentForwarding = "yes";
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ "mbessette" ];
    };
  };

  ## YubiKey auth for captain
  # Two independent credential types on the same two physical keys:
  #  - console/getty login: raw U2F/CTAP via pam_u2f, key must be physically
  #    plugged into this machine (see secret.captain-u2f-keys.age).
  #  - `su - captain` from an mbessette SSH session: FIDO2 SSH key
  #    (captainYubikeySshPubKeys above) checked against the agent forwarded
  #    over SSH, so the key can stay on the remote client and never touch
  #    this host. captain is intentionally never added to sshd's AllowUsers.
  services.udev.packages = [ pkgs.libfido2 ];

  security.pam.u2f = {
    enable = true;
    control = "sufficient"; # successful touch alone is enough -- no password fallback prompt
    settings = {
      cue = true; # print "please touch the device" while waiting
      authfile = config.age.secrets."captain-u2f-keys".path;
    };
  };
  security.pam.services.login.u2fAuth = true;

  security.pam.sshAgentAuth = {
    enable = true;
    authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ]; # matches captain's declarative authorizedKeys.keys above
  };
  security.pam.services.su.sshAgentAuth = true;

  ## VSCode Server
  services.vscode-server.enable = true;

  ## Containerization
  virtualisation.containers.enable = true;
  virtualisation.oci-containers.backend = "podman";

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
