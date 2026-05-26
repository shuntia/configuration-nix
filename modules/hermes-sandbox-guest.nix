{ lib, pkgs, ... }:

# NixOS configuration for the Hermes VM guest.
# Concern: Docker runtime + Hermes OCI container.
# Network addressing and microvm hardware are set in hermes-sandbox-vm.nix.
{
  # Minimal: Docker, Hermes, nothing else.
  virtualisation.docker = {
    enable       = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  virtualisation.oci-containers = {
    backend = "docker";

    containers.hermes = {
      image     = "nousresearch/hermes-agent:latest";
      autoStart = true;
      cmd       = [ "gateway" "run" ];

      volumes = [
        # hermes-state is a Docker named volume inside the VM, backed by the
        # persistent disk image at /var/lib/docker.  Drop the volume to get a
        # clean slate; the disk image survives.
        "hermes-state:/opt/data"
        # DooD: Hermes spawns sub-containers for tool sandboxing.
        # TERMINAL_ENV=docker below enforces this; the local backend is never used.
        "/var/run/docker.sock:/var/run/docker.sock"
      ];

      environment = {
        # Enforce Docker sandbox backend.  This env var takes precedence over
        # any value in /opt/data/.env so the user cannot accidentally enable local.
        TERMINAL_ENV = "docker";

        # Dashboard available on port 9119 for verification and daily use.
        HERMES_DASHBOARD      = "1";
        HERMES_DASHBOARD_HOST = "0.0.0.0";
        HERMES_DASHBOARD_PORT = "9119";
      };

      # Ports are exposed on all VM interfaces; the host-side firewall on
      # br-hermes is the actual access boundary — no host-external interface
      # can route to the VM's bridge IP.
      ports = [
        "8642:8642"  # OpenAI-compatible API (enable with API_SERVER_ENABLED=true in .env)
        "9119:9119"  # Dashboard
      ];
    };
  };

  # No services beyond what Docker needs.
  services.openssh.enable = lib.mkDefault false;

  system.stateVersion = "25.11";
}
