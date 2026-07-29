{ vars, ... }:
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

  # nftables backend: unifies with Podman, which auto-switches its netavark
  # firewall driver to nftables when this is set (see
  # nixos/modules/virtualisation/podman/default.nix). Under the classic
  # iptables backend, the OS firewall and netavark share one mutable INPUT
  # chain and can clobber each other's rules; nftables keeps them in
  # independent tables instead.
  networking.nftables.enable = true;
  networking.firewall.backend = "nftables"; # explicit; also the default once nftables.enable is set

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
