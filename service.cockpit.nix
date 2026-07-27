{ pkgs, vars, ... }:
{
  services.cockpit = {
    enable = true;
    port = vars.ports.cockpit;
    plugins = with pkgs; [
      cockpit-podman
      cockpit-networkmanager
      cockpit-sensors
      cockpit-file-sharing
      cockpit-zfs
    ];
  };
}
