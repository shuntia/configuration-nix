{ config, lib, pkgs, inputs, ... }:

let
  user     = "shuntia";
  fullName = "Shuntia";
  hostname = "shuntia-nix";
  tailnet  = "tail5ec9c9.ts.net";
  tsFQDN   = "${hostname}.${tailnet}";
  # Public-facing hostname (served via Cloudflare tunnel)
  cfDomain = "uwu.shuntia.net";
  rtcDomain = "matrix-rtc.${cfDomain}";
  rtcProxyPort = 8181;
  # ─── Matrix Authentication Service ────────────────────────────────────────
  authDomain  = "auth.${cfDomain}";
  masPort     = 8082;
  masPackage  = pkgsUnstable.matrix-authentication-service;
  masShareDir = "${masPackage}/share/matrix-authentication-service";
  # ULID registered as the Tuwunel OAuth client in MAS. Must match the
  # client_id in /persist/secrets/mas-client-secret and in the MAS clients
  # section below. ULIDs use Crockford base32; this one is a fixed sentinel.
  masClientId = "01JWMAS000000000000000001";
  masConfig   = pkgs.writeText "mas-config.yaml" ''
    http:
      public_base: "https://${authDomain}/"
      issuer: "https://${authDomain}/"
      listeners:
        - name: web
          resources:
            - name: discovery
            - name: human
            - name: oauth
            - name: compat
            - name: graphql
            - name: assets
              path: "${masShareDir}/assets"
          binds:
            - address: "127.0.0.1:${toString masPort}"

    templates:
      path: "${masShareDir}/templates"

    i18n:
      path: "${masShareDir}/translations"

    policy:
      wasm_module: "${masShareDir}/policy.wasm"

    database:
      uri: "postgresql:///mas?host=/var/run/postgresql"

    secrets:
      encryption_file: /persist/secrets/mas-encryption-key
      keys:
        - key_file: /persist/secrets/mas-private-key.pem

    clients:
      - client_id: "${masClientId}"
        client_auth_method: client_secret_post
        client_secret_file: /persist/secrets/mas-client-secret
        redirect_uris:
          - "https://${cfDomain}/_matrix/client/unstable/login/sso/callback/${masClientId}"
  '';

  pkgsUnstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config = config.nixpkgs.config;
  };
  # Derived from fileSystems."/".device via systemd path-escaping rules:
  # strip leading /, replace remaining / with -, append .device
  rootDeviceUnit = dev:
    lib.replaceStrings ["/"] ["-"] (lib.removePrefix "/" dev) + ".device";
in
{
  imports = [ ./hardware-configuration.nix ];

  options.private.tunnelUUID = lib.mkOption {
    type    = lib.types.str;
    default = "00000000-0000-0000-0000-000000000000";
  };

  config = {
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

    # ─── Snapshots ─────────────────────────────────────────────────────────────
    # Hourly read-only snapshots of all btrfs subvolumes with tiered retention
    # (10 hourly, 7 daily, 4 weekly, 3 monthly). Boot-time snapshots are taken
    # by the initrd wipe-root service and stored in the same .snap/ directories.
    systemd.services.btrfs-snapshot = {
      description = "Periodic btrfs snapshots of all subvolumes";
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
          awk    = "${pkgs.gawk}/bin/awk";
        in
        ''
          MNT=/run/btrfs-snap
          ${mkdir} -p "$MNT"
          ${mount} -o subvol=/ ${device} "$MNT"
          trap "${umount} $MNT 2>/dev/null || true" EXIT

          TIMESTAMP=$(${date} +%Y%m%dT%H%M%S)

          # Returns 0 only if the snapshot was created and verified by btrfs.
          snap_subvol() {
            local sv="$1"
            local target="$MNT/$sv.snap/$TIMESTAMP"
            ${mkdir} -p "$MNT/$sv.snap"
            ${btrfs} subvolume snapshot -r "$MNT/$sv" "$target" \
              && ${btrfs} subvolume show "$target" > /dev/null 2>&1
          }

          # Tiered pruning: keep 10 hourly, 7 daily, 4 weekly, 3 monthly.
          # Snapshot names must be YYYYMMDDTHHMMSS.
          tiered_prune() {
            local snap_dir="$1"
            local snaps
            snaps=$(${ls} -1d "$snap_dir"/[0-9]* 2>/dev/null | sort -r) || return 0
            [ -z "$snaps" ] && return 0

            # Annotate each path with its ISO week key (requires date for week calc).
            local annotated
            annotated=$(echo "$snaps" | while IFS= read -r s; do
              local b="''${s##*/}"
              local wk
              wk=$(${date} -d "''${b:0:4}-''${b:4:2}-''${b:6:2}" +%Y%W 2>/dev/null \
                   || echo "''${b:0:6}X")
              echo "$s $wk"
            done)

            local keep
            keep=$(echo "$annotated" | ${awk} '
              { path=$1; wk=$2
                n=split(path,a,"/"); base=a[n]
                h=substr(base,1,11); d=substr(base,1,8); m=substr(base,1,6)
                if      (!(h  in H) && length(H)<10) { H[h]=1;  print path; next }
                else if (!(d  in D) && length(D)<7)  { D[d]=1;  print path; next }
                else if (!(wk in W) && length(W)<4)  { W[wk]=1; print path; next }
                else if (!(m  in M) && length(M)<3)  { M[m]=1;  print path; next }
              }
            ')

            # Bail out rather than deleting everything if the keep set is empty.
            [ -z "$keep" ] && return 1

            echo "$snaps" | while IFS= read -r snap; do
              case "
$keep
" in
                *"
$snap
"*) ;;
                *) ${btrfs} subvolume delete "$snap" 2>/dev/null || true ;;
              esac
            done
          }

          snap_subvol @root    && tiered_prune "$MNT/@root.snap"
          snap_subvol @home    && tiered_prune "$MNT/@home.snap"
          snap_subvol @persist && tiered_prune "$MNT/@persist.snap"
        '';
    };
    systemd.timers.btrfs-snapshot = {
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
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
    networking.hostName = hostname;
    networking.networkmanager.enable = true;
    networking.networkmanager.ensureProfiles.profiles.eno2 = {
      connection = {
        id             = "eno2";
        type           = "802-3-ethernet";
        interface-name = "eno2";
      };
      ipv4.method = "auto";
      ipv6 = {
        method   = "auto";
        address1 = "2601:647:4101:a5c0::1/64";
      };
    };
    networking.firewall = {
      enable = true;
      # Globally reachable
      allowedTCPPorts = [
        22    # SSH
        7881  # MatrixRTC Livekit TCP
      ];
      allowedUDPPortRanges = [
        { from = 50100; to = 50200; } # MatrixRTC Livekit UDP range
      ];
      trustedInterfaces = [ "tailscale0" ];
      # LAN-only ports: RFC1918 (IPv4) + LAN prefix (IPv6)
      # IPv6 prefix is ISP-assigned and may change; update if so.
      extraCommands =
        let
          lanPorts  = [ 8188 11434 1234 8080 9000 ];
          ipv6Lan   = "2601:647:4101:a5c0::/64";
          v4Sources = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];
          v6Sources = [ ipv6Lan "fe80::/10" ];
          mkRule = ipt: src: port:
            "${ipt} -A nixos-fw -p tcp --dport ${toString port} -s ${src} -j nixos-fw-accept";
        in
        lib.concatMapStrings (port:
          lib.concatMapStrings (src: mkRule "iptables"  src port + "\n") v4Sources +
          lib.concatMapStrings (src: mkRule "ip6tables" src port + "\n") v6Sources
        ) lanPorts;
    };

    # ─── Fail2ban ───────────────────────────────────────────────────────────────
    services.fail2ban = {
      enable   = true;
      maxretry = 5;
      bantime  = "10m";
      bantime-increment = {
        enable       = true;
        multipliers  = "1 2 4 8 16 32 64";
        maxtime      = "168h";
        overalljails = true;
      };
      jails.sshd.settings = {
        enabled  = true;
        maxretry = 3;
      };
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

    # ─── Cloudflare tunnel ──────────────────────────────────────────────────────
    # One-time setup (run as any user before nixos-rebuild):
    #   cloudflared login
    #   cloudflared tunnel create main
    #   sudo cp ~/.cloudflared/<uuid>.json /persist/secrets/cloudflared-uwu.json
    #   cloudflared tunnel route dns main uwu.shuntia.net
    # Then replace tunnelUUID in the let block with the UUID from the JSON filename.
    services.cloudflared = {
      enable = true;
      tunnels.${config.private.tunnelUUID} = {
        credentialsFile = "/persist/secrets/cloudflared-uwu.json";
        ingress = {
          # Matrix homeserver
          ${cfDomain} = { service = "http://127.0.0.1:6167"; };
          # MatrixRTC (Livekit + JWT service)
          ${rtcDomain} = { service = "http://127.0.0.1:${toString rtcProxyPort}"; };
          # Matrix Authentication Service
          ${authDomain} = { service = "http://127.0.0.1:${toString masPort}"; };
        };
        default = "http_status:404";
      };
    };

    # ─── Power / performance ────────────────────────────────────────────────────
    services.logind.settings.Login.IdleAction = "ignore";
    services.irqbalance.enable = true;
    boot.kernel.sysctl = {
      "vm.swappiness"         = 10;
      "vm.vfs_cache_pressure" = 50;
    };

    # ─── llama.cpp server (OpenAI-compatible, GPU-accelerated) ─────────────────
    # Model file: /var/lib/llama/model.gguf  (persisted; place any GGUF there)
    # Reachable by the Hermes VM at http://10.200.100.1:8080/v1
    services.llama-cpp = {
      enable  = true;
      host    = "0.0.0.0";
      port    = 8080;
      model   = "/var/lib/llama/model.gguf";
      package = pkgs.llama-cpp.override { cudaSupport = true; };
      extraFlags = [
        "--n-gpu-layers" "999"   # offload all layers to VRAM (RTX 2080 Ti)
        "--ctx-size"     "8192"
        "--parallel"     "4"
      ];
    };

    # ─── Docker ─────────────────────────────────────────────────────────────────
    virtualisation.docker = {
      enable           = true;
      enableOnBoot     = false;
      autoPrune.enable = true;
    };
    # ─── MatrixRTC (Livekit + JWT service) ──────────────────────────────────────
    virtualisation.oci-containers = {
      backend = "docker";
      containers = {
        matrix-rtc-jwt = {
          image = "ghcr.io/element-hq/lk-jwt-service:latest";
          autoStart = true;
          environment = {
            LIVEKIT_JWT_BIND = ":8081";
            LIVEKIT_URL = "wss://${rtcDomain}";
            LIVEKIT_FULL_ACCESS_HOMESERVERS = cfDomain;
          };
          environmentFiles = [ "/persist/secrets/matrix-rtc.env" ]; # LIVEKIT_KEY/LIVEKIT_SECRET
          ports = [ "127.0.0.1:8081:8081" ];
        };
        matrix-rtc-livekit = {
          image = "livekit/livekit-server:latest";
          autoStart = true;
          cmd = [ "--config" "/etc/livekit.yaml" ];
          volumes = [ "/persist/secrets/livekit.yaml:/etc/livekit.yaml:ro" ];
          extraOptions = [ "--network=host" ];
        };
      };
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

    # ─── Shell / Hyprland / Sway ────────────────────────────────────────────────
    programs.fish.enable = true;
    programs.hyprland.enable = true;
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
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

    # ─── PostgreSQL (for MAS) ────────────────────────────────────────────────────
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "mas" ];
      ensureUsers = [{
        name = "mas";
        ensureDBOwnership = true;
      }];
    };

    # ─── Matrix Authentication Service (MAS) ────────────────────────────────────
    # Provides OIDC SSO for Tuwunel. Users click "Login with MAS" and are
    # redirected here to authenticate; Tuwunel maps the returned identity to a
    # local Matrix account. This is OIDC SSO delegation (not MSC3861 full
    # delegation — Tuwunel still owns accounts and tokens).
    #
    # One-time secret setup (run as root):
    #   openssl rand -hex 32 > /persist/secrets/mas-encryption-key
    #   openssl genrsa -out /persist/secrets/mas-private-key.pem 2048
    #   openssl rand -base64 48 | tr -d '\n' > /persist/secrets/mas-client-secret
    #   chown mas:mas /persist/secrets/mas-encryption-key \
    #                 /persist/secrets/mas-private-key.pem \
    #                 /persist/secrets/mas-client-secret
    #   chmod 400     /persist/secrets/mas-encryption-key \
    #                 /persist/secrets/mas-private-key.pem \
    #                 /persist/secrets/mas-client-secret
    users.users.mas = { isSystemUser = true; group = "mas"; };
    users.groups.mas = {};

    systemd.tmpfiles.rules = [
      "d /persist/secrets 0711 root root -"
    ];

    systemd.services.matrix-authentication-service = {
      description = "Matrix Authentication Service";
      after    = [ "network-online.target" "postgresql.service" ];
      wants    = [ "network-online.target" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type  = "simple";
        User  = "mas";
        Group = "mas";
        StateDirectory     = "mas";
        StateDirectoryMode = "0700";
        ExecStartPre = let
          preflight = pkgs.writeShellScript "mas-preflight" ''
            for f in /persist/secrets/mas-encryption-key \
                     /persist/secrets/mas-private-key.pem \
                     /persist/secrets/mas-client-secret; do
              if [[ ! -f "$f" ]]; then
                echo "MAS secret missing: $f" >&2
                exit 1
              fi
            done
            ${masPackage}/bin/mas-cli --config ${masConfig} database migrate
          '';
        in [ preflight ];
        ExecStart  = "${masPackage}/bin/mas-cli --config ${masConfig} server";
        Restart    = "on-failure";
        RestartSec = 10;
      };
    };

    # ─── Tuwunel (Matrix homeserver) ────────────────────────────────────────────
    # tuwunel <1.6.2 has a bug where FallbackAcknowledgement (used by some
    # clients during dummy UIA) incorrectly requires SSO completion, causing
    # M_FORBIDDEN on registration. Patch only applies for older versions.
    services.matrix-tuwunel = {
      enable = true;
      package = pkgsUnstable.matrix-tuwunel.overrideAttrs (old: {
        patches = (old.patches or []) ++ lib.optional
          (lib.versionOlder old.version "1.6.2")
          ./fix-uiaa-fallback-ack.patch;
      });
      settings.global = {
        server_name              = cfDomain;
        address                  = [ "127.0.0.1" ];
        port                     = [ 6167 ];
        allow_registration       = true;
        registration_token_file  = "/var/lib/tuwunel/registration-token";
        allow_federation         = true;
        yes_i_am_very_very_sure_i_want_an_open_registration_server_prone_to_abuse = false;
        well_known = {
          client = "https://${cfDomain}";
          server = "${cfDomain}:443";
          livekit_url = "https://${rtcDomain}";
        };
        identity_provider = [{
          brand              = "MAS";
          client_id          = masClientId;
          client_secret_file = "/var/lib/tuwunel/mas-client-secret";
          issuer_url         = "https://${authDomain}";
          callback_url       = "https://${cfDomain}/_matrix/client/unstable/login/sso/callback/${masClientId}";
        }];
      };
    };

    # ─── nginx (Matrix reverse proxy over Tailscale TLS) ────────────────────────
    services.nginx = {
      enable                 = true;
      recommendedProxySettings = true;
      recommendedTlsSettings   = true;
      virtualHosts.${tsFQDN} = {
        forceSSL          = true;
        sslCertificate    = "/persist/tailscale-certs/cert.crt";
        sslCertificateKey = "/persist/tailscale-certs/cert.key";
        locations."/.well-known/matrix/client" = {
          extraConfig = ''
            add_header Content-Type application/json;
            add_header Access-Control-Allow-Origin *;
            return 200 '{"m.homeserver":{"base_url":"https://${cfDomain}"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://${rtcDomain}"}]}';
          '';
        };
        locations."/.well-known/matrix/server" = {
          extraConfig = ''
            add_header Content-Type application/json;
            return 200 '{"m.server":"${cfDomain}:443"}';
          '';
        };
        locations."/" = {
          proxyPass       = "http://127.0.0.1:6167";
          proxyWebsockets = true;
        };
      };
      virtualHosts.${rtcDomain} = {
        listen = [
          { addr = "127.0.0.1"; port = rtcProxyPort; }
        ];
        locations."~ ^/(sfu/get|healthz|get_token)" = {
          proxyPass = "http://127.0.0.1:8081";
        };
        locations."/" = {
          proxyPass       = "http://127.0.0.1:7880";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
          '';
        };
      };
    };
    # tuwunel uses DynamicUser=true + PrivateUsers=true.
    # PrivateUsers maps root→nobody inside the service namespace, so a plain
    # root-owned bind mount would be unwritable. ExecStartPre runs as root
    # ('+' prefix) after the dynamic user is allocated, so chown works and
    # the service can write to the bind-mounted persist dir.
    systemd.services.tuwunel.serviceConfig = {
      ExecStartPre = let
        setup = pkgs.writeShellScript "tuwunel-persist-setup" ''
          mkdir -p /persist/tuwunel
          chown tuwunel:tuwunel /persist/tuwunel
          chmod 0700 /persist/tuwunel

          if [[ ! -s /persist/secrets/matrix-registration-token ]]; then
            echo "Missing or empty /persist/secrets/matrix-registration-token" >&2
            exit 1
          fi

          install -m 0400 -o tuwunel -g tuwunel \
            /persist/secrets/matrix-registration-token \
            /persist/tuwunel/registration-token

          if [[ ! -s /persist/secrets/mas-client-secret ]]; then
            echo "Missing or empty /persist/secrets/mas-client-secret" >&2
            exit 1
          fi

          install -m 0400 -o tuwunel -g tuwunel \
            /persist/secrets/mas-client-secret \
            /persist/tuwunel/mas-client-secret
        '';
      in [ "+${setup}" ];
      BindPaths = [ "/persist/tuwunel:/var/lib/tuwunel" ];
    };

    # ─── Draupnir (Matrix moderation bot) ─────────────────────────────────────
    services.draupnir = {
      enable = true;
      settings = {
        homeserverUrl = "https://${cfDomain}";
        # Create a private unencrypted room in your Matrix client, invite the bot,
        # then set this to the room ID (Settings → Advanced → Internal Room ID).
        managementRoom = "!2E1UE1eGAmZJW5fdqS:${cfDomain}";
        autoJoinOnlyIfManager = true;
        pantalaimon = {use = false;};
      };
      secrets.accessToken = "/persist/secrets/draupnir-access-token";
    };

    # Persist Draupnir state across reboots via impermanence (/var/lib/draupnir
    # is listed in environment.persistence above). DynamicUser is forced off so
    # systemd does not create /var/lib/draupnir as a symlink into the private
    # tmpdir (which would dangle on each boot and break namespace setup).
    # A static user owns the directory instead.
    # Pre-requisite: save the bot's access token to /persist/secrets/draupnir-access-token
    users.users.draupnir = {
      isSystemUser = true;
      group = "draupnir";
    };
    users.groups.draupnir = {};
    systemd.services.draupnir = {
      after = [ "tuwunel.service" ];
      wants = [ "tuwunel.service" ];
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "draupnir";
        Group = "draupnir";
        StateDirectory = lib.mkForce "";
      };
    };

    systemd.services.nginx.after = [ "tailscale-cert.service" ];
    systemd.services.nginx.wants = [ "tailscale-cert.service" ];

    # Fetch/renew Tailscale TLS cert; runs 2 min after boot and weekly thereafter
    systemd.services.tailscale-cert = {
      description = "Obtain/renew Tailscale TLS certificate";
      after       = [ "tailscaled.service" "network-online.target" ];
      wants       = [ "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig.Type            = "oneshot";
      serviceConfig.RemainAfterExit = true;
      script = ''
        mkdir -p /persist/tailscale-certs
        ${pkgs.tailscale}/bin/tailscale cert \
          --cert-file /persist/tailscale-certs/cert.crt \
          --key-file  /persist/tailscale-certs/cert.key \
          ${tsFQDN}
        chown root:nginx /persist/tailscale-certs/cert.key
        chmod 640        /persist/tailscale-certs/cert.key
      '';
    };
    systemd.timers.tailscale-cert = {
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnBootSec  = "2min";
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    # ─── Sunshine (Moonlight streaming) ─────────────────────────────────────────
    services.sunshine = {
      enable       = true;
      autoStart    = true;
      capSysAdmin  = true; # required for KMS/DRM display capture on Wayland
      openFirewall = true;
      applications.apps = [
        {
          name = "Desktop";
          cmd  = "${pkgs.sway}/bin/sway";
        }
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
    users.users.${user} = {
      isNormalUser = true;
      description  = fullName;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" "docker" "libvirtd" "kvm" ];
      shell        = pkgs.fish;
      linger       = true;
      hashedPasswordFile = "/persist/secrets/${user}-password";
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

    # ─── Impermanence ──────────────────────────────────────────────────────────
    # @root   — snapshot + wipe on every boot (always ephemeral)
    # @home   — snapshot + wipe only when /persist/home-wipe-flag is present
    #           (set weekly by the schedule-home-wipe timer below)
    # @persist — btrfs-snapshot timer handles snapshots; never wiped here
    boot.initrd.systemd.enable = true;

    boot.initrd.systemd.services.wipe-root = {
      description = "Snapshot/wipe @root every boot; @home when flag present";
      wantedBy    = [ "initrd.target" ];
      before      = [ "sysroot.mount" ];
      # Wait for the block device before touching btrfs; without this,
      # the mount can silently fail when DefaultDependencies=no removes
      # the implicit After=sysinit.target that would otherwise settle udev.
      after       = [ (rootDeviceUnit config.fileSystems."/".device) ];
      requires    = [ (rootDeviceUnit config.fileSystems."/".device) ];
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
          rm     = "${pkgs.coreutils}/bin/rm";
        in
        ''
          ${mkdir} -p /btrfs_tmp
          ${mount} -o subvol=/ ${device} /btrfs_tmp

          TIMESTAMP=$(${date} +%Y%m%dT%H%M%S)

          # Delete btrfs subvolumes nested under $1 before deleting the parent.
          delete_nested() {
            ${btrfs} subvolume list /btrfs_tmp \
              | grep " path $1/" \
              | awk '{print $NF}' \
              | sort -r \
              | while IFS= read -r nested; do
                  ${btrfs} subvolume delete "/btrfs_tmp/$nested" 2>/dev/null || true
                done || true
          }

          snapshot_and_wipe() {
            local subvol=$1
            delete_nested "$subvol"
            if [ -e "/btrfs_tmp/$subvol" ]; then
              ${mkdir} -p "/btrfs_tmp/$subvol.snap"
              ${btrfs} subvolume snapshot -r "/btrfs_tmp/$subvol" \
                "/btrfs_tmp/$subvol.snap/$TIMESTAMP" || true
              # If delete fails, bail out so create is never attempted on an
              # existing subvolume (which would also fail and leave things broken).
              ${btrfs} subvolume delete "/btrfs_tmp/$subvol" || return 1
            fi
            ${btrfs} subvolume create "/btrfs_tmp/$subvol"
          }

          # Snapshot @persist at every boot (no wipe); pruning handled by btrfs-snapshot timer.
          ${mkdir} -p /btrfs_tmp/@persist.snap
          ${btrfs} subvolume snapshot -r /btrfs_tmp/@persist \
            /btrfs_tmp/@persist.snap/$TIMESTAMP || true

          # Always wipe @root
          snapshot_and_wipe @root
          ${ls} -d /btrfs_tmp/@root.snap/* 2>/dev/null | sort | head -n -3 | \
            while IFS= read -r snap; do ${btrfs} subvolume delete "$snap"; done || true

          # Wipe @home only on scheduled boots; only clear the flag on success so
          # a failed wipe is automatically retried on the next boot.
          if [ -f "/btrfs_tmp/@persist/home-wipe-flag" ]; then
            if snapshot_and_wipe @home; then
              ${rm} -f "/btrfs_tmp/@persist/home-wipe-flag"
              ${ls} -d /btrfs_tmp/@home.snap/* 2>/dev/null | sort | head -n -5 | \
                while IFS= read -r snap; do ${btrfs} subvolume delete "$snap"; done || true
            fi
          fi

          ${umount} /btrfs_tmp
        '';
    };

    # Set the @home-wipe flag weekly; initrd picks it up on the next boot.
    systemd.services.schedule-home-wipe = {
      description = "Schedule @home wipe on next boot";
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/touch /persist/home-wipe-flag";
      };
    };
    systemd.timers.schedule-home-wipe = {
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
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
        "/var/lib/cloudflared"
        "/var/lib/bluetooth"
        "/var/lib/NetworkManager"
        "/etc/NetworkManager/system-connections"
        "/var/lib/docker"
        "/var/lib/libvirt"
        "/var/lib/llama"
        { directory = "/var/lib/draupnir"; user = "draupnir"; group = "draupnir"; mode = "0700"; }
        "/var/lib/mas"
        { directory = "/var/lib/postgresql"; user = "postgres"; group = "postgres"; mode = "0700"; }
      ];
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
      users.${user} = {
        directories = [
          "Documents" "Projects" "Downloads" "Pictures" "Music" "Videos"
          ".ssh" ".gnupg"
          ".local/share/keyrings"
          ".mozilla"
          ".steam" ".local/share/Steam"
          ".cache/mesa_shader_cache" ".cache/nv" ".cache/nix"
          ".cloudflared"
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
          ".config/comfy-ui"
          ".lmstudio"
          "models"
        ];
      };
    };

    # ─── Security ───────────────────────────────────────────────────────────────
    # Linux Audit daemon — logs syscall/file-access events to /var/log/audit/
    security.auditd.enable = true;
    security.audit.enable  = true;
    security.audit.rules   = [
      "-a exit,always -F arch=b64 -S execve"          # log all process execution
      "-w /etc/passwd  -p wa -k identity"              # watch passwd writes
      "-w /etc/shadow  -p wa -k identity"
      "-w /etc/sudoers -p wa -k sudoers"
      "-w /var/log     -p wa -k logs"
    ];

    # ClamAV antivirus daemon + signature auto-updater
    services.clamav = {
      daemon.enable   = true;
      updater.enable  = true;
      updater.interval = "daily";
    };

    # ─── Packages ───────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      cloudflared
      git vim tmux
      btrfs-progs
      pciutils usbutils lshw
      htop nvtopPackages.nvidia
      wget curl
      tree file unzip zip rsync

      # ── General essentials ─────────────────────────────────────────────────────
      sqlite        # embedded database
      postgresql    # psql client + server tools
      redis         # key-value store / cache
      xh            # HTTP client (curl-like, Rust)
      mtr           # network diagnostic (ping + traceroute)
      iperf3        # bandwidth testing
      whois         # WHOIS lookup
      bc            # arbitrary-precision calculator
      hexyl         # hex viewer
      bandwhich     # network usage by process

      # ── GNU toolchain ──────────────────────────────────────────────────────────
      gcc binutils gnumake autoconf automake libtool pkg-config
      gdb

      # ── LLVM toolchain ─────────────────────────────────────────────────────────
      clang llvm lld lldb

      # ── Build systems ──────────────────────────────────────────────────────────
      cmake ninja meson ccache

      # ── System monitoring / operations ─────────────────────────────────────────
      lsof iotop sysstat htop
      config.boot.kernelPackages.perf  # perf(1)
      ltrace strace

      # ── Networking ─────────────────────────────────────────────────────────────
      tcpdump inetutils dnsutils

      # ── Text / data processing ─────────────────────────────────────────────────
      gawk patch patchutils
      yq-go openssl

      # ── Compression ────────────────────────────────────────────────────────────
      zstd lz4 xz

      # ── Execution helpers ──────────────────────────────────────────────────────
      parallel expect

      # ── GStreamer ──────────────────────────────────────────────────────────────
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav
      gst_all_1.gst-vaapi

      # ── Remote Wayland ─────────────────────────────────────────────────────────
      waypipe   # SSH Wayland forwarding (like X11 forwarding, per-app)
      wayvnc    # VNC server for Wayland compositors
      wlr-randr # virtual display management for wlroots compositors

      # ── Security audit / management ────────────────────────────────────────────
      lynis          # host security auditing
      aide           # file-integrity monitoring (AIDE)
      tshark         # Wireshark CLI for packet capture/analysis
      acl attr       # POSIX ACL & xattr management
      ssh-audit      # SSH config/cipher auditor
      trivy          # vulnerability scanner (images, fs, git)
      yara           # malware pattern matching
      audit          # userspace tools for Linux Audit (ausearch, auditctl…)
    ];

    nixpkgs.config.allowUnfree = true;
    # Restrict CUDA compilation to RTX 2080 Ti (Turing, CC 7.5) only.
    # Without this, nvcc compiles for every known architecture in parallel,
    # which causes cicc to segfault (OOM) during the ollama/llama-cpp builds.
    nixpkgs.config.cudaCapabilities = [ "7.5" ];
    nixpkgs.config.cudaForwardCompat = false;

    # ─── Tmpfiles ───────────────────────────────────────────────────────────────
    # systemd requires /var/lib/private to be 0700 for DynamicUser services.
    # Enforce this explicitly so any leftover 0755 from a previous impermanence
    # bind-mount setup is corrected on every switch/boot.
    systemd.tmpfiles.rules = [
      "d /var/lib/private 0700 root root -"
    ];

    # ─── Nix settings ───────────────────────────────────────────────────────────
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
    };

    system.stateVersion = "25.11";
  };
}
