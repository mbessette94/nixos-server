# agenix rules file — evaluated by the `agenix` CLI with NO module args.
# Keep it self-contained: import static values directly, no function header.
let
  vars = import ./variables.nix;

  # User Keys
  captain = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGoZKkKwvlgxtEQQXrvi4nr//SYFk+v8iGm0IUDT4psH";
  mbessette = vars.mbessetteSshPubKey;
  users = [ captain mbessette ];

  # System Keys
  thiccdata = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvEFp3X5hei8beGgJQ4lnRkIXGpFCEaeqWuEGn+yzcW";
  systems = [ thiccdata ];

  # Secrets
  secrets = [
    "secret.pocket-id.encryption-key.age"
    "secret.traefik.cloudflare-api-token.age"
    "secret.kopia.envfile.age"
    "secret.captain-password.age"
    "secret.mbessette-password.age"
  ];
in
builtins.listToAttrs (map (name: {
  inherit name;
  value = { publicKeys = users ++ systems; };
}) secrets)
