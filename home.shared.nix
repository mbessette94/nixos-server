{ pkgs, ... }: {

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      gst = "git status";
      nix-update = "sudo nixos-rebuild switch --flake ~/nixos#thiccdata";
    };
  };

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
      # Nix shell indicator (very useful on NixOS)
      nix_shell = {
        symbol = "❄️ ";
      };
    };
  };

  # State version baseline
  home.stateVersion = "24.05";
}
