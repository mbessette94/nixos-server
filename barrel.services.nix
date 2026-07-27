{ pkgs, ... }: {
  imports = traefikRouteFiles = lib.filterAttrs (name: type:
    type == "regular" && (builtins.match "service\\..*\\.nix" name != null)
  ) (builtins.readDir self);
}
