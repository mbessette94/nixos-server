{ pkgs, ... }:
{
  imports = [
    ./home.shared.nix
  ];

  home.username = "captain";
  home.homeDirectory = "/home/captain";

  home.packages = with pkgs; [
    ghostty.terminfo # Fix for errors over ssh
  ];

  programs.atuin = {
    enable = true;
    settings = {
      search_mode = "fuzzy";
    };
  };

  # Traefik routes are now declared in Nix (see service.traefik.nix) and served
  # from the store — no more out-of-store router.*.yml symlinks here.

  # home.stateVersion is set once in home.shared.nix (imported above).
}
