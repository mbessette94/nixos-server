# firewall-rules.nix
{ config, lib, ... }:

with lib;

let
  cfg = config.networking.firewall.restrictedPorts;

  ruleOpts = { name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "Name of the firewall rule.";
      };
      port = mkOption {
        # Allow either an integer port (80) or a string range/list ("8000-8010" or "{ 80, 443 }")
        type = types.oneOf [ types.port types.str ];
        description = "Target port, port range (e.g. \"8000-8010\"), or list.";
      };
      protocol = mkOption {
        type = types.enum [ "tcp" "udp" ];
        default = "tcp";
        description = "Transport protocol (tcp or udp).";
      };
      allowedCIDRs = mkOption {
        type = types.listOf types.str;
        default = [ "0.0.0.0/0" "::/0" ];
        description = "Allowed source CIDRs. Defaults to all IPv4 and IPv6 if omitted.";
      };
    };
  };

  # This host's `networking.firewall` runs the classic iptables backend (not
  # nftables), so rules have to be emitted as `iptables`/`ip6tables` commands
  # via `extraCommands` -- `extraInputRules` is nftables-syntax-only and is
  # silently a no-op on this backend.
  formatCidrRule = rule: cidr:
    let
      cmd = if hasInfix ":" cidr then "ip6tables" else "iptables";
      # iptables port ranges use "start:end"; our option takes "start-end"
      # (matching nftables' syntax) for a nicer-looking config value.
      portStr = replaceStrings [ "-" ] [ ":" ] (toString rule.port);
    in
      "${cmd} -A nixos-fw -p ${rule.protocol} -m ${rule.protocol} -s ${cidr} --dport ${portStr} -j nixos-fw-accept";

  formatRule = ruleName: rule:
    concatMapStringsSep "\n" (formatCidrRule rule) rule.allowedCIDRs;

in {
  options.networking.firewall.restrictedPorts = mkOption {
    type = types.attrsOf (types.submodule ruleOpts);
    default = { };
    description = "Declarative map of named firewall rules.";
  };

  config = mkIf (cfg != { }) {
    networking.firewall.extraCommands =
      concatMapStringsSep "\n" (ruleName: formatRule ruleName cfg.${ruleName}) (attrNames cfg);
  };
}
