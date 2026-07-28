# Pure, argument-free attrset of static values shared across the config.
# Anything that depends on `config`/`lib` (e.g. runtime paths, readDir) lives
# in the module that uses it (see home.captain.nix), NOT here.
# `rec` so entries can reference each other (allowedCidrs -> localCidr/dockerCidr).
rec {
  # Host / domain
  hostName = "thiccdata";
  domain = "thiccdata.io";

  # ACME / notifications
  acmeEmail = "blade30912@gmail.com";

  # Alerting (ntfy)
  ntfyHost = "ntfy.${domain}";   # https vhost served via Traefik
  ntfyTopic = "server-alerts";   # topic the host publishes failure alerts to

  # Trusted internal networks (strings — bare a.b.c.d/n would be parsed as Nix paths)
  localCidr = "192.168.0.0/16";
  dockerCidr = "172.16.0.0/12";
  allowedCidrs = [
    localCidr
    dockerCidr
  ];

  # Remote/LAN backend hosts fronted by Traefik. `gateway` and `dns` double as
  # the host's default gateway and nameserver (see configuration.nix).
  hosts = {
    gateway = "192.168.1.1";        # UniFi UDM
    dns = "192.168.1.200";          # Technitium DNS
    homeAssistant = "192.168.3.45";
    neko = "172.22.0.11";           # neko container on the `web` podman network
  };

  # Permanent zfs paths
  ssdPool = "/mnt/thiccdata-ssd";
  hddPool = "/mnt/thiccdata-hdd";
  dockerZfsPool = "${ssdPool}/docker-data";
  # Per-app persistent state (container volumes, etc.) — lives on the SSD pool so
  # it's backed by ZFS. Single source of truth; modules append their own subdir.
  appDataDir = "${ssdPool}/appdata";

  # User public keys
  mbessetteSshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHC7FdwVyL71a2+7K9DFqNEiuvHO4eDh5ndS1tivimMi";

  ports = {
    gitea = 22;
    traefik-http = 80;
    traefik-https = 443;
    msmtp = 587;
    ntfy = 8090;   # host loopback -> ntfy container; local publish endpoint
    ssh = 2222;
    cockpit = 9090;
    kopia-ui = 51515;
    pocket-id = 1411;   # Pocket-ID OIDC provider (loopback -> Traefik)
    niko = "56000-56100";
    plex = [
      32400
      1900
      3005
      5353
      8324
      32410
      32412
      32413
      32414
      32469
    ];
  };
}
