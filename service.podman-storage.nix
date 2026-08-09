# Redirects Podman/containers-storage's graphroot off the root ext4 disk and
# onto the `thiccdata-ssd/docker-data` ZFS dataset (already mounted at
# /var/lib/docker -- previously leftover state from a pre-Podman Docker install
# using the `zfs` graph driver, which is why it's a forest of per-layer ZFS
# datasets rather than plain directories).
#
# Keep `driver = "overlay"` -- do NOT switch to `driver = "zfs"`. We want
# overlayfs on top of a ZFS-backed directory (the same pattern already used for
# every other app data dir in this repo -- applications/git, applications/
# postgres, etc.), not containers/storage's native ZFS graph driver, which is
# what produced the one-dataset-per-layer mess in the first place.
#
# NOTE: this file only changes *policy* (what storage.conf says). It does NOT
# perform the actual migration -- stopping containers, inventorying/preserving
# the real named-volume datasets mixed into docker-data (see
# scripts/migrate-podman-storage.sh), and destroying the abandoned layer
# datasets are manual, root-run, one-time steps. Deploying this file alone just
# means any FRESH podman state (after those manual steps) lands on ZFS instead
# of ext4 -- it will not retroactively move existing state.
{
  # DISABLED: risky for the current apply -- do not let this take effect until
  # deliberately re-enabled. See comments above for the manual migration steps
  # this policy change assumes have already happened.
  # virtualisation.containers.storage.settings.storage = {
  #   driver = "overlay";
  #   graphroot = "/thiccdata-ssd/docker-data";
  #   runroot = "/run/containers/storage"; # tmpfs -- no reason to move this off ext4/tmpfs
  # };
}
