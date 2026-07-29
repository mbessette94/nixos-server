{ config, pkgs, vars, ... }:
let
  localCidr = vars.localCidr;
  allowedCidrs = vars.allowedCidrs;
  ports = vars.ports;
in
{
  imports = [
    ./module.firewall.nix
  ];

  # Standard NixOS firewall enablement
  networking.firewall.enable = true;

  # Declaratively restrict ports to CIDRs!
  networking.firewall.restrictedPorts = {
    gitea = {
      port = ports.gitea;
      allowedCIDRs = allowedCidrs;
    };

    ssh = {
      port = ports.ssh;
      allowedCIDRs = [ localCidr ];
    };

    smb = {
      port = ports.smb;
      allowedCIDRs = [ localCidr ];
    };

    traefik-http = {
      port = ports.traefik-http;
    };

    traefik-https = {
      port = ports.traefik-https;
    };

    niko = {
      port = ports.niko;
      protocol = "udp";
    };
  };
}
