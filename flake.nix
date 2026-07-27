{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-26.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: 
  let
    specialArgs = {
      vars = import ./variables.nix;
    };
  in
  {
    nixosConfigurations.thiccdata = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = specialArgs // { inherit inputs; };
      modules = [
        inputs.agenix.nixosModules.default
        ./configuration.nix
        ./barrel.services.nix
        ./firewall.nix
      ];
    };

    homeConfigurations.captain = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      extraSpecialArgs = specialArgs // { inherit inputs; };
      modules = [
        ./home.captain.nix
      ];
    };

    homeConfigurations.mbessette = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      extraSpecialArgs = specialArgs // { inherit inputs; };
      modules = [
        ./home.mbessette.nix
      ];
    };
  };
}
