{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes-sandbox;
in
{
  # ── Options ──────────────────────────────────────────────────────────────────
  options.services.hermes-sandbox = {
    vcpus = lib.mkOption {
      type    = lib.types.ints.positive;
      default = 2;
    };
    memoryMiB = lib.mkOption {
      type    = lib.types.ints.positive;
      default = 2048;
    };
    diskSizeGiB = lib.mkOption {
      type    = lib.types.ints.positive;
      default = 20;
      description = "Size of the Docker storage volume inside the VM, in GiB.";
    };
    vmMac = lib.mkOption {
      type    = lib.types.str;
      default = "02:00:00:01:02:03";
    };
    hostAddress = lib.mkOption {
      type    = lib.types.str;
      default = "10.200.100.1";
      description = "IP assigned to br-hermes on the host; the VM's default gateway.";
    };
    vmAddress = lib.mkOption {
      type    = lib.types.str;
      default = "10.200.100.2";
      description = "Static IP assigned to the VM on br-hermes.";
    };
    prefixLength = lib.mkOption {
      type    = lib.types.int;
      default = 24;
    };
    bridgeSubnet = lib.mkOption {
      type    = lib.types.str;
      default = "10.200.100.0/24";
      description = "Network address of the br-hermes subnet, used in NAT rules.";
    };
    egress.dnsResolver = lib.mkOption {
      type    = lib.types.str;
      default = "1.1.1.1";
      description = "DNS resolver assigned to the VM.";
    };

    llm = {
      # Empty baseUrl → computed at config time as http://<hostAddress>:8080/v1
      baseUrl = lib.mkOption {
        type    = lib.types.str;
        default = "";
        description = "OpenAI-compatible base URL of the local LLM server. Defaults to http://<hostAddress>:8080/v1.";
      };
      model = lib.mkOption {
        type    = lib.types.str;
        default = "";
        description = "Model name passed as HERMES_MODEL. Empty uses whatever the server advertises as default.";
      };
    };

    matrix = {
      homeserver = lib.mkOption {
        type    = lib.types.str;
        default = "";
        description = "Matrix homeserver URL (https://…). Empty string disables the Matrix gateway.";
      };
      allowedUsers = lib.mkOption {
        type    = lib.types.listOf lib.types.str;
        default = [];
        description = "Matrix user IDs (@user:server) permitted to interact with the bot.";
      };
      encryption = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable E2EE. Requires libolm inside the container (present in the upstream image).";
      };
      requireMention = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Require @mention in rooms. DMs always respond without a mention.";
      };
    };
  };

  # ── Bridge ───────────────────────────────────────────────────────────────────
  config = {
    networking.bridges.br-hermes.interfaces = [];
    networking.interfaces.br-hermes.ipv4.addresses = [{
      address      = cfg.hostAddress;
      prefixLength = cfg.prefixLength;
    }];

    networking.networkmanager.unmanaged = [
      "interface-name:br-hermes"
      "interface-name:vm-*"
    ];

    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add", KERNEL=="vm-hermes", \
        RUN+="${pkgs.iproute2}/bin/ip link set %k master br-hermes"
    '';

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # NAT outbound — no per-destination filtering; the VM boundary is the control.
    networking.firewall.extraCommands = ''
      iptables -t nat -D POSTROUTING \
        -s ${cfg.bridgeSubnet} ! -d ${cfg.bridgeSubnet} -j MASQUERADE 2>/dev/null || true
      iptables -t nat -A POSTROUTING \
        -s ${cfg.bridgeSubnet} ! -d ${cfg.bridgeSubnet} -j MASQUERADE
    '';

    networking.firewall.extraStopCommands = ''
      iptables -t nat -D POSTROUTING \
        -s ${cfg.bridgeSubnet} ! -d ${cfg.bridgeSubnet} -j MASQUERADE 2>/dev/null || true
    '';

    environment.persistence."/persist".directories = [
      "/var/lib/microvms"
    ];
  };
}
