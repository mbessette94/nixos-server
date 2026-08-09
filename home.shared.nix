{ config, pkgs, vars, ... }: {

  home.packages = with pkgs; [
    ghostty.terminfo # Fix for errors over ssh
    nerd-fonts.jetbrains-mono
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      gst = "git status";
      nix-update = "sudo nixos-rebuild switch --flake /nixos-server#${vars.hostName}";
      home-update = "home-manager switch --flake /nixos-server#${config.home.username}";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    # Optional custom settings (translates to ~/.config/starship.toml)
    settings = {
      # Line 1: ➜ folder git:(branch) [status]
      format = "$character$directory$git_branch";

      # Show current directory name only
      directory = {
        style = "bold cyan";
        truncation_length = 1;
        truncate_to_repo = false;
      };

      # git:(branch) styling
      git_branch = {
        format = "[git:\\([$branch](red)\\)](bold blue) ";
      };

      # Bottom line prompt arrow
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
        vicmd_symbol = "[➜](bold yellow)";
      };

      git_status = {
        disabled = false;
      };

      # Nix shell indicator module configuration
      nix_shell = {
        symbol = "❄️ ";
        format = "via [$symbol$state]($style) ";
      };
    };
  };


  # State version baseline
  home.stateVersion = "24.05";
}
