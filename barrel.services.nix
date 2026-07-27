# Auto-import every service.*.nix module in this directory.
{ lib, ... }:
let
  serviceFiles = lib.filterAttrs
    (name: type: type == "regular" && builtins.match "service\\..*\\.nix" name != null)
    (builtins.readDir ./.);
in {
  imports = map (name: ./. + "/${name}") (builtins.attrNames serviceFiles);
}
