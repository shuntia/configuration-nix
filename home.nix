{ config, lib, pkgs, ... }:

{
  home.username    = "shuntia";
  home.homeDirectory = "/home/shuntia";
  home.stateVersion  = "25.11";

  # ─── Illogical Impulse (end-4 dotfiles + QuickShell) ───────────────────────
  programs.illogical-impulse.enable = true;

  # Override the upstream starship.toml with the personal config
  xdg.configFile."starship.toml" = lib.mkForce { source = ./starship.toml; };

  # ─── llama-server preset config ─────────────────────────────────────────────
  # RTX 2080 Ti (Turing, CC 7.5, 11GB VRAM). Flash-attn on for q8_0 KV cache.
  # GGML_CUDA_FA_ALL_QUANTS=ON (compiled in llama-cpp override) enables
  # aggressive cache quants on Turing if needed later.
  # Models live in /var/lib/llama/models.
  xdg.configFile."llama-cpp/llama-server.ini".text = ''
    version = 1

    ; ============================================================
    ; Global defaults — apply to every preset unless overridden
    ; ============================================================
    [global]
    host = 127.0.0.1
    port = 8080
    n-gpu-layers = 99
    flash-attn = on
    cache-type-k = q8_0
    cache-type-v = q8_0
    jinja = true
    threads = -1
    mlock = true
    ; --no-webui if you don't want the built-in chat UI on :8080
    ; no-webui = true

    ; ============================================================
    ; Qwen3 8B — daily driver. Tool calling + long context.
    ; ~5GB weights @ Q4_K_M + ~3-4GB KV cache @ 32k ctx q8_0
    ; ============================================================
    [qwen3-8b]
    model = /var/lib/llama/models/Qwen3-8B-Q4_K_M.gguf
    alias = qwen3-8b
    ctx-size = 32768
    temp = 0.7
    top-p = 0.8
    top-k = 20
    min-p = 0.0
    repeat-penalty = 1.05

    ; Same model, thinking mode tuning (Qwen3 model card recommends
    ; different sampling when /think is active).
    [qwen3-8b-think]
    model = /var/lib/llama/models/Qwen3-8B-Q4_K_M.gguf
    alias = qwen3-8b-think
    ctx-size = 32768
    temp = 0.6
    top-p = 0.95
    top-k = 20
    min-p = 0.0

    ; ============================================================
    ; Qwen3 14B — better quality, tighter context budget.
    ; ~9GB weights leaves ~2-3GB for cache → ~16k usable ctx.
    ; ============================================================
    [qwen3-14b]
    model = /var/lib/llama/models/Qwen3-14B-Q4_K_M.gguf
    alias = qwen3-14b
    ctx-size = 16384
    temp = 0.7
    top-p = 0.8
    top-k = 20
    min-p = 0.0
    repeat-penalty = 1.05

    ; ============================================================
    ; Qwen3-Coder 30B-A3B (MoE) — only active experts on GPU,
    ; the rest offloaded to system RAM. Needs 32GB+ system RAM.
    ; Use --override-tensor regex to push MoE FFN layers to CPU.
    ; ============================================================
    [qwen3-coder-30b]
    model = /var/lib/llama/models/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf
    alias = qwen3-coder
    ctx-size = 32768
    override-tensor = .ffn_.*_exps.=CPU
    temp = 0.7
    top-p = 0.8
    top-k = 20
    min-p = 0.0
    repeat-penalty = 1.05
  '';

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
      desktop       = "ssh shuntia@100.125.222.56";
      hypr-remote   = "systemctl --user start hyprland-remote";
      sway-headless = "systemctl --user start sway-headless";

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

      # llama.cpp presets
      llm8    = "llm qwen3-8b";
      llm8t   = "llm qwen3-8b-think";
      llm14   = "llm qwen3-14b";
      llmcode = "llm qwen3-coder-30b";

      # sandbox shell
      sb = ''bwrap --unshare-all --unshare-user --disable-userns --share-net --hostname TIDY --clearenv --setenv PATH "/usr/local/bin:/usr/bin:/bin" --setenv HOME "/home/tidy" --setenv USER tidy --setenv LOGNAME tidy --setenv TERM "$TERM" --tmpfs /tmp --tmpfs /home --dir /home/tidy/.config --dir /home/tidy/.local --dir /home/tidy/.cache --bind /dev/null /proc/cpuinfo --tmpfs /proc/net/ --dev /dev --proc /proc --bind $PWD /home/tidy/(basename $PWD) --die-with-parent --ro-bind /bin /bin --ro-bind /usr/bin /usr/bin --ro-bind /usr/local/bin /usr/local/bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind /usr/lib /usr/lib --ro-bind /etc/resolv.conf /etc/resolv.conf --ro-bind /etc/ssl /etc/ssl --ro-bind /usr/share/terminfo/ /usr/share/terminfo/ --chdir /home/tidy/(basename $PWD)'';
    };

    functions = {
      mark_prompt_start = {
        body    = ''echo -en "\e]133;A\e\\"'';
        onEvent = "fish_prompt";
      };
      tojapan.body = ''TZ=Asia/Tokyo date -d "$argv" "+%Y-%m-%d %H:%M JST"'';

    llm = {
      description = "Launch llama-server with a named preset";
      body = ''
        if test (count $argv) -eq 0
          echo "usage: llm <preset> [extra llama-server args...]"
          echo "presets in $LLAMA_CONFIG:"
          grep -oE '^\[[^]]+\]' $LLAMA_CONFIG | tr -d '[]' | grep -v '^global$'
          return 1
        end
        set -l preset $argv[1]
        set -e argv[1]
        llama-server --config $LLAMA_CONFIG --preset $preset $argv
      '';
    };

    llm-status = {
      description = "Check llama-server health";
      body = ''
        curl -fsS $LLAMA_API_BASE/models 2>/dev/null | jq -r '.data[].id' \
            ; or echo "llama-server not reachable at $LLAMA_API_BASE"
      '';
    };

    llm-ask = {
      description = "Send a single prompt to the loaded model";
      body = ''
        set -l prompt (string join ' ' $argv)
        curl -fsS $LLAMA_API_BASE/chat/completions \
            -H 'Content-Type: application/json' \
            -d (jq -nc --arg p "$prompt" '{
                  messages: [{role:"user", content:$p}],
                  stream: false
                }') \
            | jq -r '.choices[0].message.content'
      '';
    };

    llm-vram = {
      description = "Watch GPU VRAM during inference";
      body = ''
        nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu \
                   --format=csv -l 1
      '';
    };
    };

  shellInit = ''
    set -gx PNPM_HOME "/home/shuntia/.local/share/pnpm"
    fish_add_path $PNPM_HOME
    fish_add_path /home/shuntia/.cargo/bin

    # ─── llama.cpp environment ─────────────────────────────────────────
    set -gx LLAMA_MODELS_DIR /var/lib/llama/models
    set -gx LLAMA_CONFIG     $HOME/.config/llama-cpp/llama-server.ini
    set -gx LLAMA_API_BASE   http://127.0.0.1:8080/v1

    # llama.cpp also reads env vars in the LLAMA_ARG_* namespace; these
    # are ignored when --config is used but useful for one-off llama-cli.
    set -gx LLAMA_ARG_N_GPU_LAYERS 99
    set -gx LLAMA_ARG_FLASH_ATTN   on
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
    # llama-cpp with CUDA + full flash-attention quant support (Turing/RTX 2080 Ti)
    ((llama-cpp.override { cudaSupport = true; }).overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DGGML_CUDA_FA_ALL_QUANTS=ON" ];
    }))
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

  # ─── Otonoko Discord bot ────────────────────────────────────────────────────
  systemd.user.services.otonoko = {
    Unit = {
      Description = "Otonoko Discord music bot";
      After       = [ "network.target" ];
    };
    Service = {
      Type             = "simple";
      WorkingDirectory = "/home/shuntia/Projects/otonoko";
      ExecStart        = "${pkgs.nodejs}/bin/node /home/shuntia/Projects/otonoko/dist/bot.js";
      Restart          = "on-failure";
      RestartSec       = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

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

  xdg.configFile."sway/headless.conf".text = ''
    output HEADLESS-1 resolution 1920x1080 position 0,0

    exec ${pkgs.wayvnc}/bin/wayvnc 127.0.0.1 5900

    input type:keyboard {
      xkb_layout us
    }
  '';

  systemd.user.services.sway-headless = {
    Unit.Description = "Headless Sway session for remote VNC access";
    Service = {
      Type      = "simple";
      Environment = [
        "WLR_BACKENDS=headless"
        "WLR_LIBINPUT_NO_DEVICES=1"
        "WAYLAND_DISPLAY=wayland-remote"
        "XDG_SESSION_TYPE=wayland"
        "XDG_CURRENT_DESKTOP=sway"
      ];
      ExecStart  = "${pkgs.sway}/bin/sway -c ${config.xdg.configHome}/sway/headless.conf";
      Restart    = "on-failure";
      RestartSec = "3s";
    };
  };

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
