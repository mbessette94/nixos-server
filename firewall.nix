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

  # Allow container-originated DNS to aardvark-dns on the podman gateway IPs
  # (172.{22,23}.0.1:53, 10.88.0.1:53). Netavark's own nftables table already
  # accepts this traffic, but under the nftables backend nixos-fw's INPUT
  # chain runs independently with policy=drop -- and drop wins across tables.
  # Without this rule, aardvark listens but every container-side DNS query is
  # silently dropped by nixos-fw before it reaches aardvark. Symptom: every
  # `getent hosts <peer>` inside a container returns empty; `dig` from the
  # host works (because host-sourced packets don't come from a container CIDR).
  networking.firewall.extraInputRules = ''
    ip saddr { 172.22.0.0/24, 172.23.0.0/24, 10.88.0.0/16 } meta l4proto { tcp, udp } th dport 53 accept comment "podman container DNS to aardvark"
  '';

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
