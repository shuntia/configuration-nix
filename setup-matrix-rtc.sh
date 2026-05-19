#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CF_DOMAIN="${CF_DOMAIN:-uwu.shuntia.net}"
RTC_DOMAIN="${RTC_DOMAIN:-matrix-rtc.${CF_DOMAIN}}"
TUNNEL_NAME="${TUNNEL_NAME:-main}"

SECRETS_DIR="/persist/secrets"
ENV_FILE="${SECRETS_DIR}/matrix-rtc.env"
LIVEKIT_FILE="${SECRETS_DIR}/livekit.yaml"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

gen_alnum() {
  local len="$1"
  if command -v pwgen >/dev/null 2>&1; then
    pwgen -s -1 "${len}"
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${len}"
  fi
}

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run as an unprivileged user so cloudflared uses your user credentials." >&2
  exit 1
fi

require_cmd sudo
require_cmd cloudflared

if sudo test -e "${ENV_FILE}" || sudo test -e "${LIVEKIT_FILE}"; then
  echo "Refusing to overwrite existing files in ${SECRETS_DIR}." >&2
  exit 1
fi

sudo install -d -m 0700 "${SECRETS_DIR}"

LIVEKIT_KEY="$(gen_alnum 20)"
LIVEKIT_SECRET="$(gen_alnum 64)"

sudo install -m 0600 /dev/null "${ENV_FILE}"
sudo install -m 0600 /dev/null "${LIVEKIT_FILE}"

sudo tee "${ENV_FILE}" >/dev/null <<EOF
LIVEKIT_KEY=${LIVEKIT_KEY}
LIVEKIT_SECRET=${LIVEKIT_SECRET}
EOF

sudo tee "${LIVEKIT_FILE}" >/dev/null <<EOF
port: 7880
bind_addresses:
  - ""
rtc:
  tcp_port: 7881
  port_range_start: 50100
  port_range_end: 50200
  use_external_ip: true
  enable_loopback_candidate: false
keys:
  ${LIVEKIT_KEY}: ${LIVEKIT_SECRET}
EOF

cloudflared tunnel route dns "${TUNNEL_NAME}" "${RTC_DOMAIN}"

echo "Created ${ENV_FILE} and ${LIVEKIT_FILE} and routed ${RTC_DOMAIN} to tunnel ${TUNNEL_NAME}."
