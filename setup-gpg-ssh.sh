#!/usr/bin/env bash
# Configure GPG agent for SSH authentication on the client machine.
# Run this on the machine you SSH *from*, not the NixOS target.

set -euo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }

GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
GPG_AGENT_CONF="${GNUPGHOME}/gpg-agent.conf"
FISH_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/gpg-ssh.fish"
KEY_EMAIL="shuntia@shuntia.net"

# ─── GPG agent ────────────────────────────────────────────────────────────────
info "Configuring gpg-agent for SSH support..."
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

if grep -q "enable-ssh-support" "${GPG_AGENT_CONF}" 2>/dev/null; then
    echo "  enable-ssh-support already set."
else
    echo "enable-ssh-support" >> "${GPG_AGENT_CONF}"
    echo "  added enable-ssh-support to ${GPG_AGENT_CONF}"
fi

# ─── Add [A] subkey if missing ────────────────────────────────────────────────
info "Checking for authentication subkey..."
if gpg --list-keys "${KEY_EMAIL}" 2>/dev/null | grep -q "\[A\]"; then
    echo "  [A] subkey already exists."
else
    echo "  No [A] subkey found. Adding one now..."
    echo "  Follow the prompts: choose (8) RSA set caps → toggle S → toggle E → toggle A → Q → 4096 → 0"
    gpg --expert --edit-key "${KEY_EMAIL}" addkey save
fi

# ─── Fish shell config ────────────────────────────────────────────────────────
info "Writing fish SSH socket config to ${FISH_CONF}..."
mkdir -p "$(dirname "${FISH_CONF}")"
cat > "${FISH_CONF}" << 'FISHEOF'
# Route SSH through gpg-agent
if command -q gpgconf
    set -gx SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
    gpg-connect-agent updatestartuptty /bye &>/dev/null
end
FISHEOF
echo "  written."

# ─── Restart agent ────────────────────────────────────────────────────────────
info "Restarting gpg-agent..."
gpgconf --kill gpg-agent
gpg-connect-agent /bye 2>/dev/null || true
echo "  agent restarted."

# ─── Print public key ─────────────────────────────────────────────────────────
info "Your SSH public key (add this to authorized_keys / configuration.nix):"
echo
gpg --export-ssh-key "${KEY_EMAIL}" 2>/dev/null \
    || { echo "  Could not export — ensure the [A] subkey was created and try again."; exit 1; }
echo
echo "==> Copy the key above and run:"
echo "    nixos-rebuild switch --flake /etc/nixos#shuntia-nix"
echo "    (after updating configuration.nix with the new key)"
