{
  description = "shuntia-nix NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    illogical-flake = {
      url = "github:soymou/illogical-flake/d6ae33e596ac6d2e3c21ca92cec0c6cc17da9c70";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, impermanence, illogical-flake, zen-browser, ... }@inputs: {
    nixosConfigurations.shuntia-nix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        ./zen.nix
        impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs       = true;
            useUserPackages     = true;
            backupFileExtension = "bak";
            users.shuntia = {
              imports = [
                illogical-flake.homeManagerModules.default
                ./home.nix
              ];
            };
          };
        }
      ];
    };
  };
}
