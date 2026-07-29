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

  formatCidrRule = rule: cidr:
    let
      family = if hasInfix ":" cidr then "ip6" else "ip";
      # toString handles both integers (2222) and strings ("8000-8010") cleanly --
      # nftables accepts dash-range syntax directly in a rule statement.
      portStr = toString rule.port;
    in
      "${family} saddr ${cidr} ${rule.protocol} dport ${portStr} accept comment \"${rule.name}\"";

  formatRule = ruleName: rule:
    concatMapStringsSep "\n" (formatCidrRule rule) rule.allowedCIDRs;

in {
  options.networking.firewall.restrictedPorts = mkOption {
    type = types.attrsOf (types.submodule ruleOpts);
    default = { };
    description = "Declarative map of named firewall rules.";
  };

  config = mkIf (cfg != { }) {
    networking.firewall.extraInputRules =
      concatMapStringsSep "\n" (ruleName: formatRule ruleName cfg.${ruleName}) (attrNames cfg);
  };
}
