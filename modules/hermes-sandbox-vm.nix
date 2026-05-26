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
      networking.defaultGateway = cfg.hostAddress;
      networking.nameservers    = [ cfg.egress.dnsResolver ];

      # Open only the ports Hermes actually uses; the host firewall controls
      # which sources can actually reach them.
      networking.firewall.allowedTCPPorts = [ 8642 9119 ];

      # Matrix gateway — non-secret config only.
      # MATRIX_ACCESS_TOKEN must be placed in /opt/data/.env by the user
      # (via `docker exec -it hermes hermes gateway setup` or manually).
      virtualisation.oci-containers.containers.hermes.environment =
        lib.mkIf (cfg.matrix.homeserver != "") {
          MATRIX_HOMESERVER     = cfg.matrix.homeserver;
          MATRIX_ALLOWED_USERS  = lib.concatStringsSep "," cfg.matrix.allowedUsers;
          MATRIX_ENCRYPTION     = if cfg.matrix.encryption then "true" else "false";
          MATRIX_REQUIRE_MENTION = if cfg.matrix.requireMention then "true" else "false";
        };
    };
  };
}
