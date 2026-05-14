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

  # ─── Snapshots (snapper) ────────────────────────────────────────────────────
  # Snapshots /persist (user data). Root rollback is handled by NixOS generations.
  # First run after rebuild: sudo snapper -c persist create-config /persist
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval  = "1d";
    configs.persist = {
      SUBVOLUME          = "/persist";
      ALLOW_USERS        = [ "shuntia" ];
      TIMELINE_CREATE    = true;
      TIMELINE_CLEANUP   = true;
      TIMELINE_LIMIT_HOURLY  = "10";
      TIMELINE_LIMIT_DAILY   = "7";
      TIMELINE_LIMIT_WEEKLY  = "4";
      TIMELINE_LIMIT_MONTHLY = "3";
      TIMELINE_LIMIT_YEARLY  = "0";
    };
  };

  # ─── Swap ───────────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    priority = 100;
    memoryPercent = 50;
  };

  # ─── Networking ─────────────────────────────────────────────────────────────
  networking.hostName = "shuntia-nix";
  networking.networkmanager.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      6167  # Matrix Tuwunel
      8188  # ComfyUI
      11434 # Ollama
      1234  # LM Studio
      8080  # llama.cpp
      9000  # local testing
    ];
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
    powerManagement.enable = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # ─── Tailscale ──────────────────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ─── Power / performance ────────────────────────────────────────────────────
  services.irqbalance.enable = true;
  boot.kernel.sysctl = {
    "vm.swappiness"          = 10;
    "vm.vfs_cache_pressure"  = 50;
    # IPv6 privacy extensions — randomise host address, rotate periodically
    "net.ipv6.conf.all.use_tempaddr"     = 2;
    "net.ipv6.conf.default.use_tempaddr" = 2;
  };

  # ─── Fail2ban ───────────────────────────────────────────────────────────────
  services.fail2ban = {
    enable    = true;
    maxretry  = 5;
    bantime   = "10m";
    bantime-increment = {
      enable      = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime     = "168h";
      overalljails = true;
    };
    jails.sshd.settings = {
      enabled  = true;
      maxretry = 3;
    };
  };

  # ─── Docker ─────────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable           = true;
    enableOnBoot     = false;
    autoPrune.enable = true;
  };

  # ─── QEMU / KVM ─────────────────────────────────────────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package      = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };
  programs.virt-manager.enable = true;

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

  # ─── Polkit ─────────────────────────────────────────────────────────────────
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel") && [
        "org.freedesktop.login1.reboot",
        "org.freedesktop.login1.reboot-multiple-sessions",
        "org.freedesktop.login1.power-off",
        "org.freedesktop.login1.power-off-multiple-sessions",
        "org.freedesktop.login1.suspend",
        "org.freedesktop.login1.suspend-multiple-sessions",
        "org.freedesktop.login1.hibernate",
        "org.freedesktop.login1.hibernate-multiple-sessions",
      ].indexOf(action.id) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  # ─── Gaming ─────────────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;

  # ─── Tuwunel (Matrix homeserver) ────────────────────────────────────────────
  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name          = "shuntia-nix";
      address              = [ "0.0.0.0" ];
      port                 = [ 6167 ];
      allow_registration   = true;
      yes_i_am_very_very_sure_i_want_an_open_registration_server_prone_to_abuse = true;
      allow_federation     = false;
    };
  };

  # ─── Sunshine (Moonlight streaming) ─────────────────────────────────────────
  services.sunshine = {
    enable       = true;
    autoStart    = true;
    capSysAdmin  = true; # required for KMS/DRM display capture on Wayland
    openFirewall = true;
    applications.apps = [
      { name = "Desktop"; }
      {
        name = "Steam Big Picture";
        cmd  = "steam -gamepadui";
      }
    ];
  };

  # ─── Printing ───────────────────────────────────────────────────────────────
  services.printing = {
    enable  = true;
    drivers = [ pkgs.hplip ];
  };
  services.avahi = {
    enable   = true;
    nssmdns4 = true;
  };

  # ─── Fonts ──────────────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      inter
      nerd-fonts.meslo-lg
      nerd-fonts.jetbrains-mono
    ];
  };

  # ─── User ───────────────────────────────────────────────────────────────────
  users.users.shuntia = {
    isNormalUser = true;
    description  = "Shuntia";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "docker" "libvirtd" "kvm" ];
    shell        = pkgs.fish;
    hashedPasswordFile = "/persist/secrets/shuntia-password";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh2RGhHE6CJRdyC/AvMDEPmjFcEE/YjLER3VXYBfhNPAWTD+oUJNFVJ9OL1tpwxcCH/Ev4CPHBNS9iDSh+PlKELNRZzRuKGKH6a3LB0MVz9/+tSvT+wYGjiAvxOxjz29qOHZH41bxJc3bskP71glPxbi/krxpdI8r5s/z7oqILjwMQb9xgkxtAEXGJ+3JLGn4/cCX/cKsCR8i6bFWrh/sYRQxuzuTZBCKbaE1qR93JyObX1YGh3PAQXWYRqwfnoVg/ZiBSwZzX6lHQxPKmkSYuI2AKdWX2eXg3xmcXeEPH1zoPkLJREkdvGrXWZgrSK6ekNZLa0fGx60ahkZ8J01ycCXZALmyKPkKtP+7QEbLuVE47V7XwJjIteV5NFeuX9am1y9Vo7wm7+XPC52AAhZZh/xarCUWwtzMqG5sSSlRibd0QVarhu3oi5Betzj+DUApfMar2XYvdltVWvbr45tgCZrYLz3CoEEXzi6yeLTjcpi1W0D1xnLSRNiqLRUJJ/bjG6MBxkRZt3+t6EDoCxoJdv32mvF1rw8BZZTrMKzMHX4/NV+xWhpvhqz25HdA7O157ikcSRsCrlCa/gOzrrecnmhwT5Um480t/1ItykO6qDAy9dCJJtb6laBG/HF9tojeeN3E0XYj6ineQlun/DaYvanUpVZQG83V0/snA+Yn1Aw== openpgp:0xD6B8B7E2"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKbj82bzvetG8qKKfORDXTse5XteZpT3Dkmw33nmQLs shuntia@ShuntiArch"
    ];
  };
  security.sudo.wheelNeedsPassword = true;

  # ─── FUSE ───────────────────────────────────────────────────────────────────
  programs.fuse.userAllowOther = true;

  # ─── SSH ────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication        = false;
      KbdInteractiveAuthentication  = false;
      PermitRootLogin               = "prohibit-password";
    };
  };

  # ─── Impermanence: wipe @root and @home on every boot ──────────────────────
  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.services.wipe-root-and-home = {
    description = "Wipe @root and @home btrfs subvolumes";
    wantedBy    = [ "initrd.target" ];
    before      = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script =
      let
        device = config.fileSystems."/".device;
        btrfs  = "${pkgs.btrfs-progs}/bin/btrfs";
        mount  = "${pkgs.util-linux}/bin/mount";
        umount = "${pkgs.util-linux}/bin/umount";
        date   = "${pkgs.coreutils}/bin/date";
        ls     = "${pkgs.coreutils}/bin/ls";
        mkdir  = "${pkgs.coreutils}/bin/mkdir";
      in
      ''
        ${mkdir} -p /btrfs_tmp
        ${mount} -o subvol=/ ${device} /btrfs_tmp

        TIMESTAMP=$(${date} +%Y%m%dT%H%M%S)

        snapshot_and_wipe() {
          local subvol="$1"
          if [ -e "/btrfs_tmp/$subvol" ]; then
            ${btrfs} subvolume snapshot -r "/btrfs_tmp/$subvol" "/btrfs_tmp/$subvol-$TIMESTAMP" || true
            ${btrfs} subvolume delete "/btrfs_tmp/$subvol"
          fi
          ${btrfs} subvolume create "/btrfs_tmp/$subvol"
        }

        snapshot_and_wipe @root
        snapshot_and_wipe @home

        for prefix in @root @home; do
          ${ls} -d /btrfs_tmp/"$prefix"-* 2>/dev/null | sort | head -n -3 | \
            while IFS= read -r snap; do ${btrfs} subvolume delete "$snap"; done
        done

        ${umount} /btrfs_tmp
      '';
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot    = true;
  fileSystems."/nix".neededForBoot     = true;

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
      "/var/lib/docker"
      "/var/lib/libvirt"
      "/var/lib/matrix-tuwunel"
    ];
    files = [
      "/etc/machine-id"
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
        ".cache/mesa_shader_cache" ".cache/nv" ".cache/nix"
        # Tool state
        ".local/share/atuin"
        ".local/share/zoxide"
        ".local/share/pnpm"
        ".local/share/yazi"
        ".local/share/task"
        ".cargo"
        ".rustup"
        "go"
        ".wine"
        ".config/sunshine"
        ".lmstudio"
        "models"
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
