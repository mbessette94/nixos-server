{ config, lib, pkgs, vars, ... }:
let
  ntfyUrl = "http://127.0.0.1:${toString vars.ports.ntfy}";
  topic = vars.ntfyTopic;
  host = vars.hostName;

  # Publishes one alert to ntfy. Never fails (|| true) so a broken alerter can't
  # itself trigger OnFailure and loop. Runs as root, so journalctl can read any
  # unit's logs for context.
  notifyScript = pkgs.writeShellScript "ntfy-notify-failure" ''
    set -u
    unit="''${1:-unknown.unit}"
    body="$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 20 --no-pager -o cat 2>/dev/null)"
    [ -z "$body" ] && body="(no journal output for $unit)"
    ${pkgs.curl}/bin/curl -fsS --max-time 10 \
      -H "Title: ${host}: $unit failed" \
      -H "Priority: high" \
      -H "Tags: rotating_light" \
      --data-binary "$body" \
      "${ntfyUrl}/${topic}" || true
  '';

  # Attach this to a unit to alert when it enters the failed state. `%n` passes
  # the failing unit's own name to the template instance.
  onFailureHook = { onFailure = [ "notify-failure@%n.service" ]; };

  # Curated non-container system units to watch. These MUST already be defined
  # elsewhere in the config, or the module system would synthesize an empty,
  # ExecStart-less service. Add more unit names here as the stack grows.
  # Note: cockpit is intentionally omitted — it's socket-activated and has no
  # long-running `cockpit.service` unit to attach an OnFailure hook to.
  watchedSystemUnits = [
    "traefik"
    "kopia-server"
    "podman-networks"
    "zfs-scrub"
    "pocket-id"
  ];
in
{
  systemd.services = lib.mkMerge [
    # The alerter itself: notify-failure@<failed-unit>.service
    {
      "notify-failure@" = {
        description = "Send ntfy alert for failed unit %i";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${notifyScript} %i";
        };
      };
    }

    # Go wide #1: every oci-container, keyed by the module's own serviceName
    # (so it tracks backend/name changes) — ntfy, socket-proxy, portainer, and
    # anything added later, all covered automatically.
    (lib.mapAttrs'
      (name: container: lib.nameValuePair container.serviceName onFailureHook)
      config.virtualisation.oci-containers.containers)

    # Go wide #2: the curated system units above.
    (lib.listToAttrs (map (n: lib.nameValuePair n onFailureHook) watchedSystemUnits))
  ];
}
