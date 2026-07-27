{ config, vars, pkgs, lib, ... }:
{
  imports = [
    ./home.shared.nix
  ];

  programs.atuin = {
    enable = true;
    settings = {
      search_mode = "fuzzy";
    };
  };

  ## Map traefiks dynamic route files to captain's home
  home.file = lib.mapAttrs' (name: _: {
    name = xdg.configFile."traefik/dynamic/${name}";
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${vars.runtimeNixosSrc}/${name}";
    };
  }) vars.traefikRouteFiles;

  # State version baseline
  home.stateVersion = "24.05";
}
