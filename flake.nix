{
  description = "shuntia-nix NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    comfyui-nix.url = "github:utensils/comfyui-nix";

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    odysseus.url = "github:shuntia/odysseus";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, impermanence, illogical-flake, zen-browser, comfyui-nix, microvm, odysseus, ... }@inputs: {
    nixosConfigurations.shuntia-nix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        ./zen.nix
        comfyui-nix.nixosModules.default
        { nixpkgs.overlays = [ comfyui-nix.overlays.default ]; }
      ] ++ (if builtins.pathExists ./private.nix then [ ./private.nix ] else []) ++ [
        impermanence.nixosModules.impermanence
        microvm.nixosModules.host
        ./modules/hermes-sandbox-host.nix
        odysseus.nixosModules.default
        ./modules/hermes-sandbox-vm.nix
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
