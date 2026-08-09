{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-26.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      # Pin to the release branch that matches nixpkgs (nixos-26.05); tracking
      # master drifts ahead of the 26.05 module API and can break switches.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      vars = import ./variables.nix;

      specialArgs = {
        inherit vars;
      };
    in
    {
      # `nix fmt` — RFC-style formatter, applied tree-wide.
      formatter.${system} = pkgs.nixfmt;

      # `nix develop` — editor LSP + lint/format/secret tooling on PATH.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd # Nix language server (LSP)
          nixfmt # formatter (same as `nix fmt`; RFC-style)
          statix # lint: anti-patterns / suggestions
          deadnix # lint: dead/unused code
          inputs.agenix.packages.${system}.default # secret management
          git

          rclone # Nextcloud -> OpenCloud file migration (scripts/migrate-nextcloud.sh)
          vdirsyncer # Nextcloud -> OpenCloud CalDAV/CardDAV migration
        ];
        shellHook = ''
          echo "nixos-server dev shell — lint: 'statix check' / 'deadnix' ; format: 'nix fmt'"
        '';
      };

      nixosConfigurations.${vars.hostName} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = specialArgs // {
          inherit inputs;
        };
        modules = [
          inputs.agenix.nixosModules.default
          inputs.nixos-vscode-server.nixosModules.default
          ./configuration.nix
          ./barrel.services.nix
          ./firewall.nix
        ];
      };

      homeConfigurations.captain = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = specialArgs // {
          inherit inputs;
        };
        modules = [
          ./home.captain.nix
        ];
      };

      homeConfigurations.mbessette = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = specialArgs // {
          inherit inputs;
        };
        modules = [
          ./home.mbessette.nix
        ];
      };
    };
}
