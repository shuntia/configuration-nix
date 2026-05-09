{ config, pkgs, ... }:

{
  home.username    = "shuntia";
  home.homeDirectory = "/home/shuntia";
  home.stateVersion  = "25.11";

  # ─── Illogical Impulse (end-4 dotfiles + QuickShell) ───────────────────────
  # Module injected via flake.nix → illogical-flake.homeManagerModules.default
  programs.illogical-impulse.enable = true;

  # ─── Git ────────────────────────────────────────────────────────────────────
  programs.git = {
    enable    = true;
    userName  = "shuntia";
    userEmail = "shuntia@shuntia.net";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase        = true;
    };
  };

  # ─── Extra packages not covered by illogical-impulse ───────────────────────
  home.packages = with pkgs; [
    # Wayland utilities
    grimblast
    wl-clipboard
    cliphist
    brightnessctl
    playerctl

    # Browser
    zen-browser

    # Media
    mpv
    imv
    zathura
    spotify

    # File management
    thunar
    gvfs
    file-roller

    # Communication
    vesktop

    # Productivity
    obsidian
    libreoffice-fresh

    # System
    pavucontrol
    blueman
    networkmanagerapplet
  ];

  programs.home-manager.enable = true;
}
