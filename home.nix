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

  # ─── Neovim ─────────────────────────────────────────────────────────────────
  programs.neovim = {
    enable        = true;
    defaultEditor = true;
    viAlias       = true;
    vimAlias      = true;

    plugins = with pkgs.vimPlugins; [
      # theme + UI chrome
      catppuccin-nvim
      lualine-nvim
      bufferline-nvim
      nvim-web-devicons

      # git
      gitsigns-nvim

      # keybinding hints
      which-key-nvim

      # editing helpers
      nvim-autopairs
      comment-nvim
      indent-blankline-nvim

      # file tree
      neo-tree-nvim
      nui-nvim
      plenary-nvim

      # fuzzy finding
      telescope-nvim

      # syntax / parsing
      nvim-treesitter.withAllGrammars

      # LSP
      nvim-lspconfig

      # completion
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      cmp_luasnip
      friendly-snippets
    ];

    extraPackages = with pkgs; [
      nixd                                   # Nix
      lua-language-server                    # Lua
      rust-analyzer                          # Rust
      typescript-language-server             # TS/JS
      pyright                                # Python
      clang-tools                            # C/C++ (clangd)
      gopls                                  # Go
      zls                                    # Zig
    ];

    extraLuaConfig = ''
      vim.g.mapleader      = " "
      vim.g.maplocalleader = " "

      vim.opt.number         = true
      vim.opt.relativenumber = true
      vim.opt.expandtab      = true
      vim.opt.shiftwidth     = 2
      vim.opt.tabstop        = 2
      vim.opt.smartindent    = true
      vim.opt.wrap           = false
      vim.opt.undofile       = true
      vim.opt.termguicolors  = true
      vim.opt.scrolloff      = 8
      vim.opt.signcolumn     = "yes"
      vim.opt.cursorline     = true
      vim.opt.updatetime     = 50
      vim.opt.splitright     = true
      vim.opt.splitbelow     = true

      -- theme
      require("catppuccin").setup({
        flavour = "mocha",
        integrations = {
          bufferline = true,  gitsigns = true,
          telescope  = { enabled = true },
          treesitter = true,  which_key = true,
          indent_blankline = { enabled = true },
          native_lsp = { enabled = true },
        },
      })
      vim.cmd.colorscheme("catppuccin")

      -- status + buffer line
      require("lualine").setup({ options = { theme = "catppuccin" } })
      require("bufferline").setup({ options = { separator_style = "slant" } })
      vim.keymap.set("n", "<Tab>",      "<cmd>BufferLineCycleNext<cr>")
      vim.keymap.set("n", "<S-Tab>",    "<cmd>BufferLineCyclePrev<cr>")
      vim.keymap.set("n", "<leader>x",  "<cmd>bd<cr>")

      -- git signs
      require("gitsigns").setup()

      -- which-key
      require("which-key").setup()

      -- autopairs
      require("nvim-autopairs").setup({ check_ts = true })

      -- commenting
      require("Comment").setup()

      -- indent guides
      require("ibl").setup()

      -- file tree
      require("neo-tree").setup({
        window     = { width = 30 },
        filesystem = { filtered_items = { visible = true } },
      })
      vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>")

      -- telescope
      local tb = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", tb.find_files)
      vim.keymap.set("n", "<leader>fg", tb.live_grep)
      vim.keymap.set("n", "<leader>fb", tb.buffers)
      vim.keymap.set("n", "<leader>fd", tb.diagnostics)
      vim.keymap.set("n", "<leader>fs", tb.lsp_document_symbols)

      -- treesitter
      require("nvim-treesitter.configs").setup({
        highlight = { enable = true },
        indent    = { enable = true },
      })

      -- snippets
      require("luasnip.loaders.from_vscode").lazy_load()

      -- completion
      local cmp     = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = { expand = function(a) luasnip.lsp_expand(a.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<Tab>"] = cmp.mapping(function(fb)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fb() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fb)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fb() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources(
          { { name = "nvim_lsp" }, { name = "luasnip" } },
          { { name = "buffer" },   { name = "path" } }
        ),
      })

      -- LSP
      local lsp      = require("lspconfig")
      local caps     = require("cmp_nvim_lsp").default_capabilities()
      local on_attach = function(_, buf)
        local o = { buffer = buf }
        vim.keymap.set("n", "gd",         vim.lsp.buf.definition,    o)
        vim.keymap.set("n", "gD",         vim.lsp.buf.declaration,   o)
        vim.keymap.set("n", "gr",         vim.lsp.buf.references,    o)
        vim.keymap.set("n", "gi",         vim.lsp.buf.implementation,o)
        vim.keymap.set("n", "K",          vim.lsp.buf.hover,         o)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename,        o)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action,   o)
        vim.keymap.set("n", "<leader>lf",
          function() vim.lsp.buf.format({ async = true }) end, o)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, o)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, o)
      end

      for _, s in ipairs({
        "nixd", "lua_ls", "rust_analyzer", "ts_ls",
        "pyright", "clangd", "gopls", "zls",
      }) do
        lsp[s].setup({ capabilities = caps, on_attach = on_attach })
      end

      vim.diagnostic.config({
        virtual_text     = true,
        signs            = true,
        underline        = true,
        update_in_insert = false,
        severity_sort    = true,
      })
    '';
  };

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
      desktop    = "ssh shuntia@100.125.222.56";
      hypr-remote = "systemctl --user start hyprland-remote";

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

    # ── Audio / DAW ───────────────────────────────────────────────────────────
    reaper

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
    (lib.hiPrio (pkgs.python3.withPackages (ps: with ps; [
      requests
      rich
      httpx
      pydantic
      click
      tqdm
      pillow
      beautifulsoup4
      pygments
    ])))
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
    lmstudio
    ollama-cuda

    # ── DevOps / containers ───────────────────────────────────────────────────
    docker-compose
    gh

    # ── Filesystem ────────────────────────────────────────────────────────────
    sshfs

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

  # ─── LM Studio daemon ───────────────────────────────────────────────────────
  systemd.user.services.lmstudio-server = {
    Unit = {
      Description = "LM Studio local inference server";
      After       = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.lmstudio}/bin/lms server start";
      Restart    = "on-failure";
      Type       = "simple";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # ─── Remote Hyprland (headless + WayVNC) ───────────────────────────────────
  # Minimal Hyprland config for the headless remote session.
  # Start: systemctl --user start hyprland-remote
  # Connect: ssh -L 5900:localhost:5900 host  →  VNC to localhost:5900
  xdg.configFile."hypr/remote.conf".text = ''
    monitor = HEADLESS-1, 1920x1080@60, 0x0, 1

    exec-once = ${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 5900

    input {
      kb_layout = us
      follow_mouse = 1
    }
    general {
      gaps_in    = 5
      gaps_out   = 10
      border_size = 2
    }
    decoration {
      rounding = 8
    }
  '';

  systemd.user.services.hyprland-remote = {
    Unit.Description = "Headless Hyprland session for remote VNC access";
    Service = {
      Type       = "simple";
      Environment = [
        "WLR_BACKENDS=headless"
        "WLR_LIBINPUT_NO_DEVICES=1"
        "WAYLAND_DISPLAY=wayland-remote"
        "XDG_SESSION_TYPE=wayland"
        "XDG_CURRENT_DESKTOP=Hyprland"
      ];
      ExecStart  = "${pkgs.hyprland}/bin/Hyprland -c ${config.xdg.configHome}/hypr/remote.conf";
      Restart    = "on-failure";
      RestartSec = "3s";
    };
  };

  programs.home-manager.enable = true;
}
