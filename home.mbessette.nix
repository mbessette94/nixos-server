{ ... }:
{
  imports = [
    ./home.shared.nix
  ];

  home.username = "mbessette";
  home.homeDirectory = "/home/mbessette";

  # home.stateVersion is set once in home.shared.nix (imported above).
}
