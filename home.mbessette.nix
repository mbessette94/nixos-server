{ config, vars, pkgs, lib, ... }:
{
  imports = [
    ./home.shared.nix
  ];

  home.username = "mbessette";
  home.homeDirectory = "/home/mbessette";

  # State version baseline
  home.stateVersion = "24.05";
}
