#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PS4='+ [${BASH_SOURCE}:${LINENO}] '
BASH_XTRACEFD=2
set -x

CF_DOMAIN="${CF_DOMAIN:-uwu.shuntia.net}"
RTC_DOMAIN="${RTC_DOMAIN:-matrix-rtc.${CF_DOMAIN}}"
TUNNEL_NAME="${TUNNEL_NAME:-main}"

SECRETS_DIR="/persist/secrets"
ENV_FILE="${SECRETS_DIR}/matrix-rtc.env"
LIVEKIT_FILE="${SECRETS_DIR}/livekit.yaml"

log() {
  echo ">> $*" >&2
}

LAST_CMD=""
run() {
  LAST_CMD="$*"
  log "$LAST_CMD"
  "$@"
  LAST_CMD=""
}

trap 'echo "Error on line ${LINENO}: ${LAST_CMD:-$BASH_COMMAND} (exit $?)." >&2' ERR

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
    # Avoid pipefail SIGPIPE when head closes early.
    (
      set +o pipefail
      LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${len}"
    )
  fi
}

check_tunnel() {
  local list
  if ! list="$(cloudflared tunnel list 2>/dev/null)"; then
    echo "Failed to list tunnels. Are you logged in with cloudflared?" >&2
    return 1
  fi
  if echo "$list" | awk -v t="${TUNNEL_NAME}" 'NR>1 { if ($1==t || $2==t) found=1 } END { exit !found }'; then
    return 0
  fi
  echo "Tunnel '${TUNNEL_NAME}' not found. Available tunnels:" >&2
  echo "$list" >&2
  return 1
}

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run as an unprivileged user so cloudflared uses your user credentials." >&2
  exit 1
fi

log "Using CF_DOMAIN=${CF_DOMAIN}"
log "Using RTC_DOMAIN=${RTC_DOMAIN}"
log "Using TUNNEL_NAME=${TUNNEL_NAME}"

require_cmd sudo
require_cmd cloudflared
log "Checking cloudflared tunnels"
check_tunnel

if run sudo test -e "${ENV_FILE}" || run sudo test -e "${LIVEKIT_FILE}"; then
  echo "Refusing to overwrite existing files in ${SECRETS_DIR}." >&2
  exit 1
fi

run sudo mkdir -p "${SECRETS_DIR}"
run sudo chmod 0700 "${SECRETS_DIR}"

LIVEKIT_KEY="$(gen_alnum 20)"
LIVEKIT_SECRET="$(gen_alnum 64)"

tmp_env="$(mktemp)"
tmp_livekit="$(mktemp)"
cleanup() {
  rm -f "${tmp_env}" "${tmp_livekit}"
}
trap cleanup EXIT

log "Writing temporary secrets files"
cat > "${tmp_env}" <<EOF
LIVEKIT_KEY=${LIVEKIT_KEY}
LIVEKIT_SECRET=${LIVEKIT_SECRET}
EOF

cat > "${tmp_livekit}" <<EOF
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

run sudo mv "${tmp_env}" "${ENV_FILE}"
run sudo mv "${tmp_livekit}" "${LIVEKIT_FILE}"
run sudo chmod 600 "${ENV_FILE}" "${LIVEKIT_FILE}"
trap - EXIT

run cloudflared tunnel route dns "${TUNNEL_NAME}" "${RTC_DOMAIN}"

echo "Created ${ENV_FILE} and ${LIVEKIT_FILE} and routed ${RTC_DOMAIN} to tunnel ${TUNNEL_NAME}."
