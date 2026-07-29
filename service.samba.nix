{ vars, ... }:
{
  # Samba exists here purely so `zfs share -a` (zfs-share.service) can export
  # datasets with `sharesmb=on` (thiccdata/camera-smb, thiccdata/media,
  # thiccdata/roms — set directly on the pool, not managed by this repo).
  # ZFS shares them via `net usershare add`, which is disabled by Samba's
  # own defaults (usershare max shares = 0) until explicitly turned on below.
  services.samba = {
    enable = true;

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "netbios name" = vars.hostName;

        # Guest-only LAN shares: any failed/anonymous login maps to the
        # guest account instead of being rejected.
        "map to guest" = "Bad User";

        # Required for `zfs share -a` (net usershare) to work at all --
        # Samba ships with this feature disabled (max shares = 0).
        "usershare path" = "/var/lib/samba/usershares";
        "usershare max shares" = 100;
        "usershare allow guests" = "yes";
        "usershare owner only" = "no";
      };
    };
  };

  # Samba doesn't create its usershare directory on its own; `net usershare
  # add` fails without it.
  systemd.tmpfiles.rules = [
    "d /var/lib/samba/usershares 1770 root root - -"
  ];

  # zfs-share.service ships with `After=smb.service`, but NixOS's Samba unit
  # is named samba-smbd.service (no smb.service alias) -- so the upstream
  # ordering is silently a no-op and zfs-share races Samba at boot, failing
  # `net usershare add` for camera-smb/media/roms. Re-wire it to the real unit.
  systemd.services.zfs-share = {
    after = [ "samba-smbd.service" ];
    wants = [ "samba-smbd.service" ];
  };
}
