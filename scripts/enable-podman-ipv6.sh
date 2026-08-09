#!/usr/bin/env bash
# One-time runbook to add IPv6 to the existing public-net/private-net podman
# networks. `podman network create --ignore` (service.podman-networks.nix) is
# a no-op if a network with that name already exists, so the IPv6 subnets
# added there won't retroactively apply to the current networks -- they need
# to be removed and recreated. Every attached container gets disconnected in
# the process: NixOS-declared containers (portainer/ntfy/socket-proxy/
# opencloud) restart automatically via their systemd units; Portainer-managed
# stacks need a manual redeploy afterward.
#
# MUST be run as root (sudo) directly on the host. Run subcommands in order,
# reading the output at each step.
#
# Usage: sudo ./scripts/enable-podman-ipv6.sh <subcommand>
#   stop-containers   Stop all NixOS-declared + Portainer-managed containers
#                     (same as migrate-podman-storage.sh's subcommand).
#   remove-networks   Force-remove public-net and private-net (disconnects
#                     any still-attached containers). Prompts for confirmation.
#   status            After `nixos-rebuild switch` + container redeploy: show
#                     the recreated networks' IPAM config (confirms IPv6
#                     subnets are present) and IPv6 forwarding sysctl state.
#
# After `remove-networks`, the manual next steps are:
#   1. nixos-rebuild switch --flake ~/nixos#thiccdata
#      (restarts podman-networks.service, which recreates both networks --
#      now with IPv6, since they no longer exist for --ignore to skip)
#   2. Confirm NixOS-declared containers came back:  podman ps -a
#   3. Redeploy every Portainer-managed stack that was on public-net/
#      private-net (nextcloud, immich, gitea, mailarchive, databasus,
#      homeassistant/matter-server if applicable, etc.)
#   4. sudo ./scripts/enable-podman-ipv6.sh status
set -euo pipefail

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This subcommand must be run as root (sudo)." >&2
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  read -r -p "$prompt [type 'yes' to continue] " reply
  [ "$reply" = "yes" ] || { echo "Aborted."; exit 1; }
}

cmd_stop_containers() {
  require_root
  echo "Stopping NixOS-declared oci-containers..."
  for svc in podman-portainer podman-ntfy podman-socket-proxy podman-opencloud; do
    systemctl stop "$svc" 2>/dev/null || echo "  (skip: $svc not present/running)"
  done
  echo "Stopping all remaining containers (Portainer-managed + anything else)..."
  podman stop --all --time 30
  echo "All containers stopped. Confirm with: podman ps -a"
}

cmd_remove_networks() {
  require_root
  echo "Current public-net/private-net config:"
  podman network inspect public-net private-net 2>&1 | grep -E '"[Nn]ame"|[Ss]ubnet' || true
  confirm "Force-remove public-net and private-net (disconnects any still-attached containers)?"
  podman network rm --force public-net private-net
  echo "Removed. Next: nixos-rebuild switch --flake ~/nixos#thiccdata"
  echo "(this restarts podman-networks.service, which recreates both networks with IPv6)"
}

cmd_status() {
  echo "--- IPv6 forwarding sysctl ---"
  sysctl net.ipv6.conf.all.forwarding
  echo
  echo "--- public-net / private-net IPAM ---"
  podman network inspect public-net private-net 2>&1 | grep -E '"[Nn]ame"|[Ss]ubnet|EnableIPv6'
  echo
  echo "--- containers currently attached ---"
  podman ps -a --format "table {{.Names}}\t{{.Networks}}\t{{.Status}}"
}

case "${1:-}" in
  stop-containers) cmd_stop_containers ;;
  remove-networks) cmd_remove_networks ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 {stop-containers|remove-networks|status}" >&2
    exit 1
    ;;
esac
