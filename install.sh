#!/usr/bin/env bash
# NixOS one-shot flake installer for shuntia-desktop
# Disks already partitioned & BTRFS subvolumes already exist.
#   nvme0n1: p1=EFI  p2=swap  p3=BTRFS (RAID1 primary)
#   nvme1n1: p1=EFI  p2=swap  p3=BTRFS (RAID1 mirror)
#   BTRFS subvols: @nix @root @root.snap @home @home.snap @persist @persist.snap

set -euo pipefail

DISK_A=/dev/nvme0n1
DISK_B=/dev/nvme1n1
MNT=/mnt
BTRFS_OPTS="compress=zstd:3,noatime"
NIXOS_DIR="${MNT}/etc/nixos"
CFG_DIR="/root/nixos-config"   # flake evaluated from here, outside /mnt

# ─── Helpers ──────────────────────────────────────────────────────────────────
die()     { echo "ERROR: $*" >&2; exit 1; }
info()    { echo; echo "==> $*"; }
confirm() {
    read -r -p "${1:-Continue?} [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
}

# ─── Sanity checks ────────────────────────────────────────────────────────────
info "Checking prerequisites..."
[[ $EUID -eq 0 ]]    || die "Must run as root."
[[ -b "${DISK_A}" ]] || die "${DISK_A} not found."
[[ -b "${DISK_B}" ]] || die "${DISK_B} not found."
command -v nixos-generate-config &>/dev/null || die "nixos-generate-config not found — boot from NixOS ISO."
command -v nixos-install         &>/dev/null || die "nixos-install not found — boot from NixOS ISO."
command -v nix                   &>/dev/null || die "nix not found — boot from NixOS ISO."

# Ensure flakes are available
export NIX_CONFIG="experimental-features = nix-command flakes"

# ─── Swap ─────────────────────────────────────────────────────────────────────
info "Activating swap..."
swapon "${DISK_A}p2" 2>/dev/null && echo "  ${DISK_A}p2 activated" \
    || echo "  ${DISK_A}p2 skipped (already on or not swap)"
swapon "${DISK_B}p2" 2>/dev/null && echo "  ${DISK_B}p2 activated" \
    || echo "  ${DISK_B}p2 skipped (already on or not swap)"

# ─── Root (@root subvolume) ───────────────────────────────────────────────────
info "Mounting @root at ${MNT}..."
mount -t btrfs -o "subvol=@root,${BTRFS_OPTS}" "${DISK_A}p3" "${MNT}"

# ─── BTRFS subvolumes ─────────────────────────────────────────────────────────
info "Scanning BTRFS devices..."
btrfs device scan

mount_sub() {
    local subvol="$1" mp="$2"
    mkdir -p "${MNT}/${mp}"
    mount -t btrfs -o "subvol=${subvol},${BTRFS_OPTS}" "${DISK_A}p3" "${MNT}/${mp}"
    echo "  ${subvol}  →  ${MNT}/${mp}"
}

info "Mounting BTRFS subvolumes..."
mount_sub @nix     nix
mount_sub @home    home
mount_sub @persist persist

# ─── EFI partitions ───────────────────────────────────────────────────────────
info "Mounting EFI partitions..."
mkdir -p "${MNT}/boot"
mount "${DISK_A}p1" "${MNT}/boot"
echo "  ${DISK_A}p1  →  ${MNT}/boot"

mkdir -p "${MNT}/boot.bak"
mount "${DISK_B}p1" "${MNT}/boot.bak"
echo "  ${DISK_B}p1  →  ${MNT}/boot.bak"

# ─── Hardware config ──────────────────────────────────────────────────────────
info "Generating hardware-configuration.nix..."
nixos-generate-config --root "${MNT}"
mkdir -p "${CFG_DIR}"
cp "${NIXOS_DIR}/hardware-configuration.nix" "${CFG_DIR}/"
echo "  generated at ${CFG_DIR}/hardware-configuration.nix"

# ─── Password ─────────────────────────────────────────────────────────────────
info "Set password for user 'shuntia'..."
PASSWD_HASH=""
while [[ -z "$PASSWD_HASH" ]]; do
    pw1="" pw2=""
    read -r -s -p "  Enter password for shuntia: " pw1 || true; echo
    read -r -s -p "  Confirm password:           " pw2 || true; echo
    if [[ -z "$pw1" ]]; then
        echo "  Password cannot be empty, try again."
    elif [[ "$pw1" != "$pw2" ]]; then
        echo "  Passwords do not match, try again."
    else
        PASSWD_HASH=$(printf '%s\n' "$pw1" | mkpasswd -m sha-512 -s) || true
    fi
done
echo "  Password hashed OK."

# ─── flake.nix ────────────────────────────────────────────────────────────────
info "Writing flake.nix..."
cat > "${CFG_DIR}/flake.nix" << 'FLAKEEOF'
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
FLAKEEOF
echo "  written to ${CFG_DIR}/flake.nix"

# ─── configuration.nix ────────────────────────────────────────────────────────
info "Writing configuration.nix..."
cat > "${CFG_DIR}/configuration.nix" << 'NIXEOF'
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ─── Boot ────────────────────────────────────────────────────────────
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

  boot.plymouth = { enable = true; theme = "spinner"; };

  # ─── Filesystem maintenance ───────────────────────────────────────────
  services.btrfs.autoScrub = { enable = true; interval = "monthly"; };
  services.fstrim.enable = true;
  services.smartd = { enable = true; autodetect = true; };

  # ─── Swap ────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    priority = 100;
    memoryPercent = 50;
  };

  # ─── Networking ──────────────────────────────────────────────────────
  networking.hostName = "shuntia-desktop";
  networking.networkmanager.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # ─── Locale ──────────────────────────────────────────────────────────
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # ─── Graphics / NVIDIA ───────────────────────────────────────────────
  hardware.graphics = { enable = true; enable32Bit = true; };
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # ─── Tailscale ───────────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ─── Display manager ─────────────────────────────────────────────────
  services.displayManager.ly.enable = true;

  # ─── Shell / Hyprland ────────────────────────────────────────────────
  programs.fish.enable = true;
  programs.hyprland.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # ─── Audio ───────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  security.rtkit.enable = true;

  # ─── Gaming ──────────────────────────────────────────────────────────
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;

  # ─── User ────────────────────────────────────────────────────────────
  users.users.shuntia = {
    isNormalUser = true;
    description  = "Shuntia";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
    shell        = pkgs.fish;
    hashedPassword = "__PASSWD_HASH__";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH/xDdlT5xAcqOfolRQ/TTuwCope9Zpanjv6j9rH9dtj shuntia@shuntia.net"
    ];
  };
  security.sudo.wheelNeedsPassword = true;

  # ─── SSH ─────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication       = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin              = "prohibit-password";
    };
  };

  # ─── Impermanence: wipe @home on every boot ──────────────────────────
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

  # ─── Packages ────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git vim neovim tmux
    btrfs-progs
    pciutils usbutils lshw
    htop nvtopPackages.nvidia
    wget curl
    tree file unzip zip rsync
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store   = true;
  };

  system.stateVersion = "25.11";
}
NIXEOF
sed -i "s|__PASSWD_HASH__|${PASSWD_HASH}|" "${CFG_DIR}/configuration.nix"
echo "  written to ${CFG_DIR}/configuration.nix"

# ─── home.nix ─────────────────────────────────────────────────────────────────
info "Writing home.nix..."
cat > "${CFG_DIR}/home.nix" << 'HOMEEOF'
{ config, pkgs, ... }:

{
  home.username      = "shuntia";
  home.homeDirectory = "/home/shuntia";
  home.stateVersion  = "25.11";

  # end-4 Hyprland dotfiles + QuickShell (via illogical-flake input in flake.nix)
  programs.illogical-impulse.enable = true;

  programs.git = {
    enable    = true;
    userName  = "shuntia";
    userEmail = "shuntia@shuntia.net";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase        = true;
    };
  };

  home.packages = with pkgs; [
    grimblast
    wl-clipboard
    cliphist
  ];

  programs.home-manager.enable = true;
}
HOMEEOF
echo "  written to ${CFG_DIR}/home.nix"

# ─── Summary & install ────────────────────────────────────────────────────────
info "Mount summary:"
findmnt --list --output TARGET,SOURCE,FSTYPE,OPTIONS | grep "^${MNT}" | sed 's/^/  /'

echo
echo "Config files in ${CFG_DIR}:"
ls -1 "${CFG_DIR}/" | sed 's/^/  /'
echo
info "Locking flake inputs (generates flake.lock before nix hashes the directory)..."
nix flake lock "${CFG_DIR}"

echo "About to run: nixos-install --flake ${CFG_DIR}#shuntia-desktop --root ${MNT} --no-root-passwd"
confirm "Install NixOS now?"

nixos-install --flake "${CFG_DIR}#shuntia-desktop" --root "${MNT}" --no-root-passwd

# Copy configs into the installed system for future nixos-rebuild
info "Copying config into ${NIXOS_DIR} for persistence..."
mkdir -p "${NIXOS_DIR}"
cp "${CFG_DIR}"/*.nix "${CFG_DIR}/flake.lock" "${NIXOS_DIR}/"
echo "  done."

# ─── Reboot ───────────────────────────────────────────────────────────────────
info "Installation complete."
confirm "Reboot now?"
reboot
