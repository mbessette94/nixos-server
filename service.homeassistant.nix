{ vars, pkgs, ... }:
let
  dataDirectory = "${vars.appDataDir}/applications";
in
{
  # Migrated from a Portainer-managed docker-compose stack. Both containers
  # share a macvlan network on enp6s0 (vars.net.podmanInterface, previously
  # left unmanaged/"reserved for Podman/Docker" in configuration.nix) so they
  # get real LAN-routable IPs for mDNS/SSDP/Matter discovery -- a bridge
  # network wouldn't work for this. IPs/MACs match the original compose file
  # exactly (192.168.3.45/.46) so the existing Traefik routing in
  # service.traefik.nix (vars.hosts.homeAssistant) keeps working unchanged.
  systemd.services.podman-network-lan-macvlan = {
    description = "Create the LAN-facing macvlan podman network (${vars.net.podmanInterface})";
    wantedBy = [ "multi-user.target" ];
    after = [
      "podman.service"
      "network-online.target"
      "sys-subsystem-net-devices-${vars.net.podmanInterface}.device"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.podman ];
    script = ''
      podman network create --ignore -d macvlan -o parent=${vars.net.podmanInterface} \
        --subnet 192.168.3.0/24 --gateway 192.168.3.1 lan-macvlan
    '';
  };

  virtualisation.oci-containers.containers.homeassistant = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    autoStart = true;

    volumes = [
      "${dataDirectory}/homeassistant:/config"
      "/etc/localtime:/etc/localtime:ro"
    ];

    # Sonoff Zigbee 3.0 USB Dongle Plus (Silicon Labs CP210x, 10c4:ea60).
    # by-id (not by-path) so this survives reboots/re-enumeration/moving to a
    # different USB port.
    devices = [
      "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_986baee6e16bef118c329badc169b110-if00-port0:/dev/ttyUSB0"
    ];

    networks = [ "lan-macvlan:ip=${vars.hosts.homeAssistant},mac=8a:01:0c:fc:4c:0e" ];

    # Macvlan containers don't inherit host DNS -- point at the LAN gateway,
    # matching the original compose config.
    extraOptions = [ "--dns=192.168.3.1" ];
  };

  virtualisation.oci-containers.containers.matter-server = {
    image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
    autoStart = true;

    volumes = [
      "${dataDirectory}/matter-server:/data"
      "/run/dbus:/run/dbus:ro"
    ];

    networks = [ "lan-macvlan:ip=192.168.3.46,mac=66:eb:dc:e5:70:9b" ];

    extraOptions = [
      "--security-opt=apparmor=unconfined"
      "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      "--sysctl=net.ipv6.conf.all.forwarding=1"
    ];
  };

  systemd.services.podman-homeassistant = {
    after = [ "podman-network-lan-macvlan.service" ];
    requires = [ "podman-network-lan-macvlan.service" ];
  };

  systemd.services.podman-matter-server = {
    after = [ "podman-network-lan-macvlan.service" ];
    requires = [ "podman-network-lan-macvlan.service" ];
  };
}
