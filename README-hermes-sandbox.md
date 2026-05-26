# Hermes Sandbox

Hermes Agent (Nous Research) running inside a microVM on the host, sandboxed by a dedicated network bridge with a default-deny egress firewall.

## Architecture

```
host (shuntia-nix)
  └─ br-hermes (10.200.100.1/24)  ← NAT outbound, default-deny egress
       └─ hermes-vm (10.200.100.2) ← microvm.nix / QEMU
            └─ hermes container    ← nousresearch/hermes-agent:latest
                 └─ tool containers (Docker-in-Docker via socket)
```

The host firewall intercepts all FORWARD traffic from `br-hermes` via the `hermes-fw-egress` chain.  Only DNS (53/udp+tcp) to the configured resolver and HTTPS (443/tcp) to the configured allowlist are permitted.  Everything else is dropped at the host — the VM itself cannot enforce this.

The Hermes Docker sandbox backend (`TERMINAL_ENV=docker`) is enforced via the container's environment, which takes precedence over any value in `/opt/data/.env`.

## Bring-up

### 1. One-time: lock down egress

Open `modules/hermes-sandbox-host.nix` and flip `egress.allowRegistries` to `false` once the initial image pull is confirmed (see step 4).  Default is `true` to allow the pull on first boot.

### 2. Rebuild and switch

```sh
sudo nixos-rebuild switch --flake .#shuntia-nix
```

This starts the `microvms.target` and, by extension, `microvm@hermes-vm.service`.

### 3. Verify the VM is up

```sh
systemctl status microvm@hermes-vm.service
```

### 4. Confirm initial image pull succeeds

The `hermes` container will pull `nousresearch/hermes-agent:latest` on first start.  Watch it:

```sh
# From the host, journal for the VM's container unit:
journalctl -u microvm@hermes-vm.service -f
# Or exec into the VM:
systemd-run --machine hermes-vm -- docker logs -f hermes
```

Once the pull completes and Hermes starts, flip `egress.allowRegistries = false` in `hermes-sandbox-host.nix`, rebuild, and verify step 5 still passes.

### 5. Verify egress policy

From a shell inside the VM:

```sh
systemd-run --machine hermes-vm -- bash -c "curl -m 5 https://example.com"   # must FAIL
systemd-run --machine hermes-vm -- bash -c "curl -m 5 https://api.anthropic.com"  # must succeed (HTTP 4xx is fine, timeout is not)
```

### 6. Reach the dashboard

```sh
curl http://10.200.100.2:9119/
```

### 7. Configure API keys

Exec a shell into the running container to run the setup wizard, or write keys directly:

```sh
systemd-run --machine hermes-vm -- docker exec -it hermes bash
# Inside: hermes setup   (or edit /opt/data/.env directly)
```

## Log inspection

```sh
# VM unit log (QEMU stdout, microvm lifecycle events)
journalctl -u microvm@hermes-vm.service

# Hermes container log
systemd-run --machine hermes-vm -- docker logs hermes

# Follow live
systemd-run --machine hermes-vm -- docker logs -f hermes

# Egress ipset refresh log
journalctl -u hermes-egress-refresh.service
```

## State reset (drop all Hermes memory and skills)

```sh
# Stop the VM
systemctl stop microvm@hermes-vm.service

# Exec a shell into the stopped VM's Docker (start VM without Hermes autostart first)
# ... or mount the image and delete the Docker volume directory manually.
# Simplest: wipe and recreate the named volume
systemctl start microvm@hermes-vm.service
systemd-run --machine hermes-vm -- docker stop hermes
systemd-run --machine hermes-vm -- docker rm hermes
systemd-run --machine hermes-vm -- docker volume rm hermes-state
# The oci-containers unit will recreate the container and volume on next start:
systemd-run --machine hermes-vm -- systemctl restart docker-hermes.service
```

Restarting the VM after this produces a freshly-initialized Hermes with no prior memory, sessions, or installed skills.

## Clean rebuild without losing state

The `hermes-state` Docker volume lives inside the VM's persistent disk image (`/var/lib/microvms/hermes-vm/hermes-docker.img`).  Rebuilding the host or VM configuration leaves this image untouched:

```sh
sudo nixos-rebuild switch --flake .#shuntia-nix
```

microvm.nix will update the runner symlink; on the next `systemctl restart microvm@hermes-vm.service` the new VM config is loaded with the same disk image.

To rebuild the VM's NixOS layer only (without a full host switch):

```sh
# Not needed in normal operation; the VM config is rebuilt as part of the host.
```

## Egress allowlist — adding or removing a host

All allowed HTTPS destinations live in **one place**: `egress.allowedHosts` in `modules/hermes-sandbox-host.nix`.

```nix
egress.allowedHosts = [
  "api.anthropic.com"
  "api.openai.com"      # add
];
```

After changing the list, rebuild the host config.  The ipset will be repopulated at the next timer tick (≤10 min) or immediately:

```sh
sudo systemctl start hermes-egress-refresh.service
```

To remove an entry, delete it from `allowedHosts` and rebuild.

### Registry access

Set `egress.allowRegistries = true` in `modules/hermes-sandbox-host.nix`, rebuild, pull the image, then flip it back to `false`.  Registries are never needed during normal agent operation.

## Matrix gateway

### 1. Create a bot account on Tuwunel

```sh
# Use your registration token to create @hermes:uwu.shuntia.net
curl -X POST https://uwu.shuntia.net/_matrix/client/v3/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "hermes",
    "password": "<choose a password>",
    "auth": {
      "type": "m.login.registration_token",
      "token": "'$(cat /persist/secrets/matrix-registration-token)'"
    }
  }'
```

### 2. Get an access token

```sh
curl -X POST https://uwu.shuntia.net/_matrix/client/v3/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": "@hermes:uwu.shuntia.net"},
    "password": "<password from step 1>",
    "initial_device_display_name": "Hermes Agent"
  }'
# Copy the access_token from the response.
```

### 3. Configure the NixOS module

In `modules/hermes-sandbox-host.nix` (or wherever you override options):

```nix
services.hermes-sandbox.matrix = {
  homeserver    = "https://uwu.shuntia.net";
  allowedUsers  = [ "@shuntia:uwu.shuntia.net" ];
  encryption    = true;
  requireMention = true;   # set false to respond to all room messages
};
```

Rebuild: `sudo nixos-rebuild switch --flake .#shuntia-nix`

### 4. Drop the access token into the persistent volume

The token is a secret — it lives in `/opt/data/.env` inside the container (persisted in the `hermes-state` Docker volume), not in the Nix config.

```sh
systemd-run --machine hermes-vm -- \
  docker exec hermes sh -c \
  'echo "MATRIX_ACCESS_TOKEN=<token>" >> /opt/data/.env'

# Restart the container to pick it up:
systemd-run --machine hermes-vm -- \
  systemctl restart docker-hermes.service
```

### 5. Verify

Invite `@hermes:uwu.shuntia.net` to a Matrix room or DM.  The bot auto-accepts and responds.

Check logs:

```sh
systemd-run --machine hermes-vm -- docker logs hermes 2>&1 | grep -i matrix
```

You should see `Matrix: connected` and `Matrix: syncing`.

### E2EE cross-signing (optional but recommended)

If your account has cross-signing enabled (Element default), add your recovery key so the bot self-verifies on each start:

```sh
systemd-run --machine hermes-vm -- \
  docker exec hermes sh -c \
  'echo "MATRIX_RECOVERY_KEY=<recovery key from Element Settings→Security>" >> /opt/data/.env'
```

Without this, Element may show the bot's device as unverified and withhold encryption sessions.

## Notes

- `api.anthropic.com` (and other CDN-fronted endpoints) resolves to rotating Cloudflare IPs.  The 10-minute ipset refresh reduces stale-entry 443 timeouts but does not eliminate them.  A brief pause on the first request after an IP rotation is normal.
- The `hermes-docker.img` disk image is stored under `/var/lib/microvms/` and persisted via impermanence.  btrfs hourly snapshots include it (copy-on-write, so snapshots are fast).  `tar` the image file for off-host backups.
- The VM has no GPU passthrough.  Hermes will use whatever LLM API endpoint you configure.
- SSH into the VM is disabled by default (`services.openssh.enable = false` in the guest).  Use `systemd-run --machine hermes-vm` for host-side exec, or enable SSH via `services.hermes-sandbox.sshd` if added later.
