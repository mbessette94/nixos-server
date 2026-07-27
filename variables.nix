{ config, lib }:
{
  runtimeNixosSrc = "${config.users.users.captain.home}/nixos";

  traefikRouteFiles = lib.filterAttrs (name: type:
    type == "regular" && (builtins.match "route\\..*\\.toml" name != null)
  ) (builtins.readDir runtimeNixosSrc);

  allowedCidrs = [
    192.168.1.1/16
    172.16.0.0/12
  ];

  mbessetteSshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHC7FdwVyL71a2+7K9DFqNEiuvHO4eDh5ndS1tivimMi";
}
