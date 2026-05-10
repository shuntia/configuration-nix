{ config, lib, pkgs, ... }:

{
  home.username    = "shuntia";
  home.homeDirectory = "/home/shuntia";
  home.stateVersion  = "25.11";

  # ─── Illogical Impulse (end-4 dotfiles + QuickShell) ───────────────────────
  programs.illogical-impulse.enable = true;

  # Override the upstream starship.toml with the personal config
  xdg.configFile."starship.toml" = lib.mkForce { source = ./starship.toml; };

  # ─── Git ────────────────────────────────────────────────────────────────────
  programs.git = {
    enable   = true;
    settings = {
      user.name  = "shuntia";
      user.email = "shuntia@shuntia.net";
      init.defaultBranch = "main";
      pull.rebase        = true;
    };
  };

  # ─── Shell tools ────────────────────────────────────────────────────────────
  programs.zoxide  = { enable = true; enableFishIntegration = true; };
  programs.atuin   = { enable = true; enableFishIntegration = true; };
  programs.direnv  = { enable = true; nix-direnv.enable = true; };
  programs.fzf     = { enable = true; enableFishIntegration = true; };
  programs.lazygit.enable = true;

  # ─── Fish configuration ──────────────────────────────────────────────────────
  programs.fish = {
    enable = true;

    shellAliases = {
      ls = "eza --icons --group-directories-first -1";
    };

    shellAbbrs = {
      # ls shortcuts (expand to alias)
      l   = "ls";
      ll  = "ls -l";
      la  = "ls -a";
      lla = "ls -la";

      # git
      lg  = "lazygit";
      g   = "git";
      gd  = "git diff";
      ga  = "git add .";
      gc  = "git commit -am";
      gl  = "git log";
      gs  = "git status";
      gst = "git stash";
      gsp = "git stash pop";
      gp  = "git push";
      gpl = "git pull";
      gsw = "git switch";
      gsm = "git switch main";
      gb  = "git branch";
      gbd = "git branch -d";
      gco = "git checkout";
      gsh = "git show";

      # cargo / rust
      ca  = "cargo add";
      c   = "cargo";
      cr  = "cargo run";
      cb  = "cargo build";
      crr = "cargo run --release";
      cbr = "cargo build --release";
      ct  = "cargo test";
      ch  = "cargo hot";

      # pnpm
      p  = "pnpm";
      px = "pnpx";
      pi = "pnpm i";
      pu = "pnpm update";

      # systemctl
      s   = "sudo";
      sc  = "sudo systemctl";
      scr = "sudo systemctl restart";
      sce = "sudo systemctl enable";
      scd = "sudo systemctl disable";
      scs = "sudo systemctl start";
      us  = "systemctl --user";
      j   = "journalctl";
      sr  = "systemctl soft-reboot";

      # misc
      rm  = "trash";
      rmf = "rm -f";
      cl  = "clear";
      n   = "nvim";
      x   = "exit";
      nvx = "nohup neovide . >>/dev/null & disown;exit";
      kbl = "brightnessctl --device tpacpi::kbd_backlight set";
      rr  = "ritsu-server & ritsu start & disown ; disown";

      # remote
      desktop = "ssh shuntia@100.125.222.56";

      # system update (NixOS)
      update = "sudo nixos-rebuild switch --flake ~/projects/configuration#shuntia-nix; rustup update; pnpm update -g --latest";

      # nighttime mode
      nighttime = "killall hypridle;brightnessctl --device intel_backlight set 0;brightnessctl --device tpacpi::kbd_backlight set 0;wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 100%";

      # docker
      d  = "docker";
      dc = "docker compose";
      dps = "docker ps";

      # tools
      y       = "yazi";
      lapwing   = "cat ~/shuntools/lapwing-base.txt | fzf -e";
      container = "make -C /home/shuntia/projects/seL4-CAmkES-L4v-dockerfiles user HOST_DIR=(pwd)";

      # sandbox shell
      sb = ''bwrap --unshare-all --unshare-user --disable-userns --share-net --hostname TIDY --clearenv --setenv PATH "/usr/local/bin:/usr/bin:/bin" --setenv HOME "/home/tidy" --setenv USER tidy --setenv LOGNAME tidy --setenv TERM "$TERM" --tmpfs /tmp --tmpfs /home --dir /home/tidy/.config --dir /home/tidy/.local --dir /home/tidy/.cache --bind /dev/null /proc/cpuinfo --tmpfs /proc/net/ --dev /dev --proc /proc --bind $PWD /home/tidy/(basename $PWD) --die-with-parent --ro-bind /bin /bin --ro-bind /usr/bin /usr/bin --ro-bind /usr/local/bin /usr/local/bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind /usr/lib /usr/lib --ro-bind /etc/resolv.conf /etc/resolv.conf --ro-bind /etc/ssl /etc/ssl --ro-bind /usr/share/terminfo/ /usr/share/terminfo/ --chdir /home/tidy/(basename $PWD)'';
    };

    functions = {
      mark_prompt_start = {
        body    = ''echo -en "\e]133;A\e\\"'';
        onEvent = "fish_prompt";
      };
      tojapan.body = ''TZ=Asia/Tokyo date -d "$argv" "+%Y-%m-%d %H:%M JST"'';
    };

    shellInit = ''
      set -gx PNPM_HOME "/home/shuntia/.local/share/pnpm"
      fish_add_path $PNPM_HOME
      fish_add_path /home/shuntia/.cargo/bin
    '';

    interactiveShellInit = ''
      cat ~/.local/state/caelestia/sequences.txt 2>/dev/null
    '';
  };

  # ─── Packages ───────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # ── Wayland utilities ────────────────────────────────────────────────────
    grimblast
    wl-clipboard
    cliphist
    brightnessctl
    playerctl

    # ── Browsers ─────────────────────────────────────────────────────────────
    firefox
    chromium

    # ── Media ────────────────────────────────────────────────────────────────
    mpv
    vlc
    imv
    zathura
    spotify
    termusic
    obs-studio
    yt-dlp
    ffmpeg

    # ── Graphics / creative ───────────────────────────────────────────────────
    gimp
    inkscape
    krita

    # ── File management ───────────────────────────────────────────────────────
    thunar
    gvfs
    file-roller

    # ── Communication ─────────────────────────────────────────────────────────
    vesktop

    # ── Productivity ──────────────────────────────────────────────────────────
    obsidian
    libreoffice-fresh
    bitwarden-desktop
    qbittorrent
    pandoc

    # ── System / UI ───────────────────────────────────────────────────────────
    pavucontrol
    blueman
    networkmanagerapplet

    # ── Gaming ────────────────────────────────────────────────────────────────
    prismlauncher
    wine
    winetricks

    # ── Development: runtimes ─────────────────────────────────────────────────
    rustup
    pnpm
    nodejs           # npm / npx
    deno
    go
    uv               # fast Python package manager
    jdk              # OpenJDK
    dotnet-sdk       # C# / .NET
    ruby
    lua
    luarocks
    zig

    # ── Development: build / tooling ──────────────────────────────────────────
    just
    mold             # fast linker
    nasm
    sccache
    stylua
    prettier
    neovide

    # ── Development: analysis / debug ─────────────────────────────────────────
    hyperfine
    tokei
    valgrind
    strace
    nmap
    socat
    gdb

    # ── AI / ML ───────────────────────────────────────────────────────────────
    llama-cpp

    # ── DevOps / containers ───────────────────────────────────────────────────
    docker-compose
    gh

    # ── CLI utilities ─────────────────────────────────────────────────────────
    fastfetch
    trash-cli
    ripgrep
    fd
    bat
    jq
    btop
    bottom           # btm
    yazi
    lf
    youtube-tui
    zellij
    tmux
    tldr
    gdu
    age              # encryption
    asciinema
    taskwarrior3
    sl
    wget
    unzip
    p7zip
    file
  ];

  programs.home-manager.enable = true;
}
