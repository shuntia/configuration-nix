{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ─── Boot ──────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
    consoleMode = "max";
    extraInstallCommands = ''
      ${pkgs.rsync}/bin/rsync -a --delete /boot/ /boot.bak/
    '';
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "quiet" "splash"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
  ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  boot.plymouth = {
    enable = true;
    theme = "spinner";
  };

  # ─── Filesystem maintenance ─────────────────────────────────────────────────
  services.btrfs.autoScrub = { enable = true; interval = "monthly"; };
  services.fstrim.enable = true;
  services.smartd   = { enable = true; autodetect = true; };

  # ─── Swap ───────────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    priority = 100;
    memoryPercent = 50;
  };

  # ─── Networking ─────────────────────────────────────────────────────────────
  networking.hostName = "shuntia-desktop";
  networking.networkmanager.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # ─── Locale ─────────────────────────────────────────────────────────────────
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # ─── Graphics / NVIDIA ──────────────────────────────────────────────────────
  hardware.graphics = { enable = true; enable32Bit = true; };
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # ─── Tailscale ──────────────────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ─── Display manager ────────────────────────────────────────────────────────
  services.displayManager.ly.enable = true;

  # ─── Shell / Hyprland ───────────────────────────────────────────────────────
  programs.fish.enable = true;
  programs.hyprland.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # ─── Audio ──────────────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  security.rtkit.enable = true;

  # ─── Gaming ─────────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;

  # ─── User ───────────────────────────────────────────────────────────────────
  users.users.shuntia = {
    isNormalUser = true;
    description  = "Shuntia";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
    shell        = pkgs.fish;
    hashedPassword = ""; # populated by install.sh via mkpasswd
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH/xDdlT5xAcqOfolRQ/TTuwCope9Zpanjv6j9rH9dtj shuntia@shuntia.net"
    ];
  };
  security.sudo.wheelNeedsPassword = true;

  # ─── SSH ────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication        = false;
      KbdInteractiveAuthentication  = false;
      PermitRootLogin               = "prohibit-password";
    };
  };

  # ─── Impermanence: wipe @home on every boot ─────────────────────────────────
  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.services.wipe-home = {
    description = "Wipe @home btrfs subvolume";
    wantedBy    = [ "initrd.target" ];
    before      = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    path   = [ pkgs.btrfs-progs pkgs.util-linux ];
    script = ''
      mkdir -p /btrfs_tmp
      mount -o subvol=/ /dev/disk/by-label/nixos /btrfs_tmp
      if [ -e /btrfs_tmp/@home ]; then
        btrfs subvolume delete /btrfs_tmp/@home
      fi
      btrfs subvolume create /btrfs_tmp/@home
      umount /btrfs_tmp
    '';
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot    = true;

  fileSystems."/boot".options     = [ "umask=0077" ];
  fileSystems."/boot.bak".options = [ "umask=0077" ];

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/tailscale"
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      "/etc/shadow"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
    users.shuntia = {
      directories = [
        "Documents" "Projects" "Downloads" "Pictures" "Music" "Videos"
        ".ssh" ".gnupg"
        ".local/share/keyrings"
        ".mozilla"
        ".steam" ".local/share/Steam"
        ".cache/mesa_shader_cache" ".cache/nv"
      ];
    };
  };

  # ─── Packages ───────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git vim neovim tmux
    btrfs-progs
    pciutils usbutils lshw
    htop nvtopPackages.nvidia
    wget curl
    tree file unzip zip rsync
  ];

  nixpkgs.config.allowUnfree = true;

  # ─── Nix settings ───────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };

  system.stateVersion = "25.11";
}
