{ pkgs, vars, ... }: {

  programs.zsh = {
    enable = true;
    # enableCompletion = true;
    # autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      gst = "git status";
      nix-update = "sudo nixos-rebuild switch --flake ~/nixos#${vars.hostName}";
      home-update = "home-manager switch --flake ~/nixos#$($USER)";
    };
  };

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # State version baseline
  home.stateVersion = "24.05";
}
