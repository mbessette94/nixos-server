{ config, vars, pkgs, lib, ... }:
let
  # Where the flake is checked out on the running host (captain's home).
  runtimeNixosSrc = "${config.home.homeDirectory}/nixos";

  # Discover Traefik dynamic route files from the flake source at eval time.
  traefikRouteFiles = lib.filterAttrs
    (name: type: type == "regular" && builtins.match "router\\..*\\.yml" name != null)
    (builtins.readDir ./.);
in
{
  imports = [
    ./home.shared.nix
  ];

  home.username = "captain";
  home.homeDirectory = "/home/captain";

  programs.atuin = {
    enable = true;
    settings = {
      search_mode = "fuzzy";
    };
  };

  ## Symlink Traefik's dynamic route files into captain's home so the file
  ## provider (see service.traefik.nix) picks them up. Out-of-store symlinks
  ## point at the live checkout so edits apply without a rebuild.
  home.file = lib.mapAttrs' (name: _: {
    name = ".config/traefik/dynamic/${name}";
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${runtimeNixosSrc}/${name}";
    };
  }) traefikRouteFiles;

  # State version baseline
  home.stateVersion = "24.05";
}
