{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes-sandbox;
in
{
  # VM resources: sizing, tap interface, persistent Docker storage.
  # The inline config below is merged by microvm.nix's eval-config with the
  # microvm NixOS module (nixos-modules/microvm) automatically — no explicit
  # import of inputs.microvm.nixosModules.microvm is needed here.
  microvm.vms.hermes-vm = {
    autostart  = true;
    inherit pkgs;

    config = {
      imports = [ ./hermes-sandbox-guest.nix ];

      microvm = {
        hypervisor = "qemu";
        vcpu       = cfg.vcpus;
        mem        = cfg.memoryMiB;

        interfaces = [{
          type = "tap";
          id   = "vm-hermes";  # host-side tap name; udev rule enslaves it to br-hermes
          mac  = cfg.vmMac;
        }];

        volumes = [{
          image      = "hermes-docker.img";
          mountPoint = "/var/lib/docker";
          size       = cfg.diskSizeGiB * 1024;
        }];
      };

      # Static network: one interface, no DHCP, host is the default gateway.
      networking.usePredictableInterfaceNames = false;
      networking.interfaces.eth0.ipv4.addresses = [{
        address      = cfg.vmAddress;
        prefixLength = cfg.prefixLength;
      }];
      networking.defaultGateway = { address = cfg.hostAddress; interface = "eth0"; };
      networking.nameservers    = [ cfg.egress.dnsResolver ];

      # Open only the ports Hermes actually uses; the host firewall controls
      # which sources can actually reach them.
      networking.firewall.allowedTCPPorts = [ 8642 9119 ];

      # Non-secret config injected from host options.
      # MATRIX_ACCESS_TOKEN must be placed in /opt/data/.env by the user.
      # OPENAI_API_KEY is a placeholder; llama.cpp accepts any non-empty value.
      virtualisation.oci-containers.containers.hermes.environment =
        let
          effectiveUrl = if cfg.llm.baseUrl != ""
                         then cfg.llm.baseUrl
                         else "http://${cfg.hostAddress}:8080/v1";
        in
          {
            OPENAI_BASE_URL = effectiveUrl;
            OPENAI_API_KEY  = "sk-llama";
          }
          // lib.optionalAttrs (cfg.llm.model != "") {
            HERMES_MODEL = cfg.llm.model;
          }
          // lib.optionalAttrs (cfg.matrix.homeserver != "") {
            MATRIX_HOMESERVER      = cfg.matrix.homeserver;
            MATRIX_ALLOWED_USERS   = lib.concatStringsSep "," cfg.matrix.allowedUsers;
            MATRIX_ENCRYPTION      = if cfg.matrix.encryption then "true" else "false";
            MATRIX_REQUIRE_MENTION = if cfg.matrix.requireMention then "true" else "false";
          };
    };
  };
}
