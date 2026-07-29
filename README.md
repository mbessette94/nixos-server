# nixos-server (`thiccdata`)

Declarative NixOS config for a single self-hosted home server (`thiccdata`,
`x86_64-linux`, `nixos-26.05`). Rootless-Podman containers behind Traefik with
Cloudflare DNS-01 wildcard TLS, agenix-encrypted secrets, ZFS storage, Kopia
backups, ntfy failure-alerting, and Pocket-ID OIDC.

## Layout

The repo is flat; organization is by **filename prefix**, not folders:

| Prefix | Purpose |
|---|---|
| `configuration.nix` | Main host module (ZFS, networking, users, SSH, Podman, base pkgs). |
| `flake.nix` | Flake entrypoint: the `thiccdata` NixOS system + two home-manager configs, plus `formatter` and `devShells`. |
| `variables.nix` | Pure, argument-free attrset of shared static values (hostname, domain, CIDRs, ZFS paths, port map, pubkey). No `config`/`lib` deps. |
| `barrel.services.nix` | Auto-importer: globs and imports **every** `service.*.nix`. Drop-in a new `service.foo.nix` and it's live. |
| `service.*.nix` | One native/container service each (traefik, socket-proxy, podman-networks, portainer, kopia, ntfy, notify, cockpit, pocket-id). |
| `module.firewall.nix` + `firewall.nix` | Custom `networking.firewall.restrictedPorts` option + its rule data. |
| `home.*.nix` | home-manager: `home.shared.nix` (zsh/starship/fonts, imported by both) + per-user `home.captain.nix` / `home.mbessette.nix`. |
| `secret.*.age` + `secrets.nix` | agenix-encrypted secrets (intentionally committed) + the recipient rules file. |

> **Note on the barrel importer:** because `service.*.nix` files are discovered
> via `builtins.readDir`, *any* matching file is activated globally. To disable a
> service, remove (or stop importing) its file.

Each Traefik route also carries an `enable` flag (default `true`) if you want to
turn one off without deleting it:

```nix
services.traefik.routes.gateway.enable = false;   # stop routing gateway.<domain>
```

## Rebuild

The flake is checked out at `~/nixos` on the host (in `captain`'s home).

```sh
# System (run on the host):
sudo nixos-rebuild switch --flake ~/nixos#thiccdata   # alias: `nix-update`

# Home-manager (per user):
home-manager switch --flake ~/nixos#captain
home-manager switch --flake ~/nixos#mbessette
```

## ⚠️ hardware-configuration.nix

`hardware-configuration.nix` is currently an **empty placeholder** — it holds no
bootloader, root/boot filesystem, initrd, or swap, so the flake **cannot build a
bootable system on its own**. Regenerate it on the host and commit the result
(it contains no secrets):

```sh
nixos-generate-config --show-hardware-config | sudo tee ~/nixos/hardware-configuration.nix
```

## ⚠️ Restoring the host SSH key before first boot

`secrets.nix` encrypts every secret to this host's SSH host key (the
`ed25519` public key listed there under `systems`). That key pair was
pre-generated and is stored on a separate drive — it must be restored to
the target filesystem **before** the first `nixos-rebuild switch`/activation,
or agenix won't be able to decrypt anything (passwords, Cloudflare token,
etc.) and the boot will fail to bring up those services.

During `nixos-install`, after mounting the target filesystem but before
running the install:

```sh
mkdir -p /mnt/etc/ssh
cp /mnt/thiccdata-ssd/keys/thiccdata_id_ed25519 /mnt/etc/ssh/ssh_host_ed25519_key
cp /mnt/thiccdata-ssd/keys/thiccdata_id_ed25519.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
```

(If instead you're already booted into a live NixOS install, copy to
`/etc/ssh/` directly and `systemctl restart sshd` before the first
`nixos-rebuild switch`, so agenix can decrypt on that very first activation.)

## Secrets (agenix)

Secrets are `age`-encrypted to the recipients in `secrets.nix` (both user keys +
the host key) and committed as `*.age`. To add/rotate:

```sh
nix develop            # brings `agenix` onto PATH
agenix -e secret.foo.age    # edit/create (uses secrets.nix rules)
agenix -r                   # re-key all secrets after changing recipients
```

## Dev tooling

```sh
nix develop        # nixd (LSP), nixfmt, statix, deadnix, agenix, git on PATH
nix fmt            # format all .nix (nixfmt-rfc-style)
statix check       # lint: anti-patterns
deadnix            # lint: dead code
nix flake check    # evaluate everything
```
