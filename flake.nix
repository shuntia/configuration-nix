{
  description = "shuntia-desktop NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, impermanence, illogical-flake, ... }: {
    nixosConfigurations.shuntia-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
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
