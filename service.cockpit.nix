{ pkgs, ... }:
{
  services.cockpit = {
    enable = true;
    port = 9090;
    plugins = with pkgs; [
      cockpit-podman
      cockpit-networkmanager
      cockpit-sensors
      cockpit-file-sharing
      cockpit-zfs
    ];
  };
}
