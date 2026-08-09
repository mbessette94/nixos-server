#!/usr/bin/env bash
# Migrate per-user data from Nextcloud (cloud.thiccdata.io) to OpenCloud
# (drive.thiccdata.io): files via rclone (WebDAV -> WebDAV), calendars/contacts
# via vdirsyncer (CalDAV/CardDAV -> CalDAV/CardDAV, requires OpenCloud's Radicale
# integration to be enabled -- see service.opencloud.nix).
#
# Run via `nix develop` (provides rclone + vdirsyncer) from the repo root:
#   NEXTCLOUD_URL=https://cloud.thiccdata.io \
#   OPENCLOUD_URL=https://drive.thiccdata.io \
#   ./scripts/migrate-nextcloud.sh --dry-run alice
#
# Safe to re-run: rclone sync and vdirsyncer sync are both idempotent, so run
# once for the initial bulk copy and again right before cutover to catch deltas.
# Re-running with the same user list picks up changes made since the last run.
#
# NOT covered (per OpenCloud's own migration docs): shares, public links,
# trash, and file versions. Handle those manually or accept the loss.
set -euo pipefail

: "${NEXTCLOUD_URL:?set NEXTCLOUD_URL, e.g. https://cloud.thiccdata.io}"
: "${OPENCLOUD_URL:?set OPENCLOUD_URL, e.g. https://drive.thiccdata.io}"

DRY_RUN=0
SYNC_FILES=1
SYNC_DAV=1
USERS=()

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--files-only|--dav-only] <user> [<user> ...]

Env vars (per-user credentials -- app passwords, not account passwords):
  NEXTCLOUD_URL, OPENCLOUD_URL   base URLs (required)
  NC_USER_<user>_PASS            Nextcloud app password for <user>
  OC_USER_<user>_PASS            OpenCloud app password for <user>
  (<user> is uppercased with non-alnum chars replaced by _ for the var name)

Example:
  NEXTCLOUD_URL=https://cloud.thiccdata.io \\
  OPENCLOUD_URL=https://drive.thiccdata.io \\
  NC_USER_ALICE_PASS=xxxx OC_USER_ALICE_PASS=yyyy \\
  $0 --dry-run alice
EOF
  exit 1
}

[ $# -eq 0 ] && usage

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --files-only) SYNC_DAV=0; shift ;;
    --dav-only) SYNC_FILES=0; shift ;;
    -h|--help) usage ;;
    *) USERS+=("$1"); shift ;;
  esac
done

[ ${#USERS[@]} -eq 0 ] && usage

VDIRSYNCER_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$VDIRSYNCER_TMPDIR"' EXIT

env_var_name() {
  # alice -> ALICE, jane.doe -> JANE_DOE
  echo "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_'
}

sync_files_for_user() {
  local user="$1" nc_pass_var oc_pass_var nc_pass oc_pass
  nc_pass_var="NC_USER_$(env_var_name "$user")_PASS"
  oc_pass_var="OC_USER_$(env_var_name "$user")_PASS"
  nc_pass="${!nc_pass_var:?set $nc_pass_var}"
  oc_pass="${!oc_pass_var:?set $oc_pass_var}"

  echo "==> [$user] files: rclone sync (Nextcloud -> OpenCloud)"
  local rclone_args=(sync)
  [ "$DRY_RUN" -eq 1 ] && rclone_args+=(--dry-run)
  rclone_args+=(
    --progress
    ":webdav,url=${NEXTCLOUD_URL}/remote.php/dav/files/${user}/,user=${user},pass=$(rclone obscure "$nc_pass"):"
    ":webdav,url=${OPENCLOUD_URL}/remote.php/dav/files/${user}/,user=${user},pass=$(rclone obscure "$oc_pass"):"
  )
  rclone "${rclone_args[@]}"
}

sync_dav_for_user() {
  local user="$1" nc_pass_var oc_pass_var nc_pass oc_pass config_file status_dir
  nc_pass_var="NC_USER_$(env_var_name "$user")_PASS"
  oc_pass_var="OC_USER_$(env_var_name "$user")_PASS"
  nc_pass="${!nc_pass_var:?set $nc_pass_var}"
  oc_pass="${!oc_pass_var:?set $oc_pass_var}"

  config_file="${VDIRSYNCER_TMPDIR}/${user}.config"
  status_dir="${VDIRSYNCER_TMPDIR}/${user}.status"
  mkdir -p "$status_dir"

  cat > "$config_file" <<EOF
[general]
status_path = "${status_dir}"

[pair nextcloud_to_opencloud_cal]
a = "nc_cal_${user}"
b = "oc_cal_${user}"
collections = ["from a", "from b"]

[storage nc_cal_${user}]
type = "caldav"
url = "${NEXTCLOUD_URL}/remote.php/dav/"
username = "${user}"
password = "${nc_pass}"

[storage oc_cal_${user}]
type = "caldav"
url = "${OPENCLOUD_URL}/caldav/"
username = "${user}"
password = "${oc_pass}"

[pair nextcloud_to_opencloud_card]
a = "nc_card_${user}"
b = "oc_card_${user}"
collections = ["from a", "from b"]

[storage nc_card_${user}]
type = "carddav"
url = "${NEXTCLOUD_URL}/remote.php/dav/"
username = "${user}"
password = "${nc_pass}"

[storage oc_card_${user}]
type = "carddav"
url = "${OPENCLOUD_URL}/carddav/"
username = "${user}"
password = "${oc_pass}"
EOF

  echo "==> [$user] CalDAV/CardDAV: vdirsyncer discover + sync"
  local vdirsyncer_args=(--config "$config_file")
  vdirsyncer "${vdirsyncer_args[@]}" discover nextcloud_to_opencloud_cal
  vdirsyncer "${vdirsyncer_args[@]}" discover nextcloud_to_opencloud_card
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    (dry-run: skipping actual vdirsyncer sync -- discover only)"
  else
    vdirsyncer "${vdirsyncer_args[@]}" sync nextcloud_to_opencloud_cal
    vdirsyncer "${vdirsyncer_args[@]}" sync nextcloud_to_opencloud_card
  fi
}

for user in "${USERS[@]}"; do
  [ "$SYNC_FILES" -eq 1 ] && sync_files_for_user "$user"
  [ "$SYNC_DAV" -eq 1 ] && sync_dav_for_user "$user"
done

echo "Done. Re-run before cutover to pick up deltas."
