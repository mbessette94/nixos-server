#!/usr/bin/env bash
# Podman storage migration runbook: root ext4 (/var/lib/containers/storage) ->
# ZFS (thiccdata-ssd/docker-data). Implements the sequence from the storage
# review: identify+preserve real named-volume datasets mixed into docker-data
# (some are abandoned image/container layers from a pre-Podman Docker install,
# some are live data -- e.g. a Palworld save), then repoint Podman at the
# dataset via the Nix override in service.podman-storage.nix.
#
# MUST be run as root (sudo) directly on the host -- this is NOT something the
# assistant that wrote this script can execute; it only has read-only host
# access. Run each subcommand deliberately, in order, reading the output at
# each step. Nothing here is a single blind "do everything" button on purpose:
# the volume-identification step requires a human to look at file contents and
# decide what's worth keeping.
#
# Usage: sudo ./scripts/migrate-podman-storage.sh <subcommand>
#   inventory              List docker-data's non-layer (volume-shaped) child
#                          datasets and, for each, a peek at its contents, so
#                          you can decide what to keep. READ-ONLY.
#   snapshot               Recursive ZFS snapshot of docker-data before any
#                          destructive step. Cheap, always do this first.
#   stop-containers        Stop all NixOS-declared + Portainer-managed
#                          containers (rootful podman, one instance covers
#                          both).
#   preserve <id> <name>   Rename a volume dataset out of the way, e.g.:
#                          preserve 5yvdbmbx1e0aaqsy4lyufejh6 palworld
#                          Run this for every dataset from `inventory` you
#                          decided to keep, BEFORE destroy-layers.
#   destroy-layers         Destroy every remaining docker-data child dataset
#                          whose name is a 64-char hex layer ID (abandoned
#                          Docker image/container layers). Skips anything
#                          already renamed via `preserve`. Prompts for
#                          confirmation.
#   destroy-legacy-mount   Destroy thiccdata/docker_mount (269G, /mnt/docker) --
#                          confirmed stale (last modified 2023, unreferenced by
#                          current config, no volume-shaped datasets found in
#                          it). Prompts for confirmation.
#   status                 Show current graphroot in use (from storage.conf)
#                          and remaining dataset counts. Run after
#                          `nixos-rebuild switch` + `systemctl restart podman`
#                          to verify the migration took effect.
set -euo pipefail

DATASET="thiccdata-ssd/docker-data"
MOUNTPOINT="/var/lib/docker"
LEGACY_DATASET="thiccdata/docker_mount"
HEX64_RE='^[0-9a-f]{64}(-init)?$'

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

cmd_inventory() {
  require_root
  echo "Non-layer (likely volume) datasets under ${DATASET}:"
  echo
  zfs list -H -o name -r "$DATASET" | awk -F'/' '{print $NF}' | grep -vE "$HEX64_RE" | grep -v '^docker-data$' | while read -r id; do
    echo "--- ${id} ---"
    zfs list -o name,used,creation "${DATASET}/${id}" 2>/dev/null || true
    find "${MOUNTPOINT}/${id}" -maxdepth 3 2>/dev/null | head -20
    echo
  done
  echo "For each dataset above worth keeping, run:"
  echo "  sudo $0 preserve <id> <descriptive-name>"
}

cmd_snapshot() {
  require_root
  local snap="${DATASET}@pre-migration-$(date +%Y%m%d-%H%M%S)"
  zfs snapshot -r "$snap"
  echo "Created: $snap"
  zfs list -t snapshot -r "$DATASET"
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

cmd_preserve() {
  require_root
  local id="${1:?usage: preserve <dataset-id> <name>}"
  local name="${2:?usage: preserve <dataset-id> <name>}"
  local src="${DATASET}/${id}"
  local dst="${DATASET}/preserved-${name}"
  zfs list "$src" >/dev/null # fail loudly if it doesn't exist
  zfs rename "$src" "$dst"
  echo "Renamed ${src} -> ${dst}"
  echo "Reattach this to its recreated container's volume mount after redeploy."
}

cmd_destroy_layers() {
  require_root
  echo "The following abandoned layer datasets will be destroyed:"
  zfs list -H -o name -r "$DATASET" | awk -F'/' '{print $NF}' | grep -E "$HEX64_RE" | tee /tmp/podman-migration-layers-to-destroy.txt
  local count
  count="$(wc -l < /tmp/podman-migration-layers-to-destroy.txt)"
  echo "($count datasets)"
  confirm "Destroy all $count datasets listed above? This is irreversible (snapshot from 'snapshot' subcommand is your safety net)."
  while read -r id; do
    zfs destroy -r "${DATASET}/${id}"
  done < /tmp/podman-migration-layers-to-destroy.txt
  rm -f /tmp/podman-migration-layers-to-destroy.txt
  echo "Done. Remaining datasets under ${DATASET}:"
  zfs list -r "$DATASET"
}

cmd_destroy_legacy_mount() {
  require_root
  echo "About to destroy: ${LEGACY_DATASET} (confirmed stale -- last modified 2023, unreferenced)"
  zfs list "$LEGACY_DATASET"
  confirm "Destroy ${LEGACY_DATASET}? This is irreversible."
  zfs destroy -r "$LEGACY_DATASET"
  echo "Destroyed."
}

cmd_status() {
  echo "--- storage.conf ---"
  grep -E 'driver|graphroot|runroot' /etc/containers/storage.conf || true
  echo
  echo "--- podman info (graphRoot) ---"
  podman info --format '{{.Store.GraphRoot}} (driver: {{.Store.GraphDriverName}})' 2>&1 || echo "(podman info failed -- run as a user with podman access, or via sudo)"
  echo
  echo "--- remaining datasets under ${DATASET} ---"
  zfs list -r "$DATASET" 2>&1 || true
}

case "${1:-}" in
  inventory) cmd_inventory ;;
  snapshot) cmd_snapshot ;;
  stop-containers) cmd_stop_containers ;;
  preserve) shift; cmd_preserve "$@" ;;
  destroy-layers) cmd_destroy_layers ;;
  destroy-legacy-mount) cmd_destroy_legacy_mount ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 {inventory|snapshot|stop-containers|preserve <id> <name>|destroy-layers|destroy-legacy-mount|status}" >&2
    exit 1
    ;;
esac
