#!/usr/bin/env bash
set -euo pipefail

HOMESERVER="https://shuntia-nix.tail5ec9c9.ts.net"
SERVER_NAME="shuntia-nix.tail5ec9c9.ts.net"
TOKEN_FILE="/persist/secrets/matrix-admin-token"

usage() {
  echo "Usage: $0 <username> [password]"
  echo "  username  — local part only (e.g. 'alice', not '@alice:...')"
  echo "  password  — if omitted, a random one is generated"
  exit 1
}

[[ $# -lt 1 ]] && usage

USERNAME="$1"
PASSWORD="${2:-$(tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 20)}"

if [[ -f "$TOKEN_FILE" ]]; then
  ADMIN_TOKEN="$(cat "$TOKEN_FILE")"
elif [[ -n "${MATRIX_ADMIN_TOKEN:-}" ]]; then
  ADMIN_TOKEN="$MATRIX_ADMIN_TOKEN"
else
  echo "Error: no admin token found."
  echo "Either put it in $TOKEN_FILE or set MATRIX_ADMIN_TOKEN."
  exit 1
fi

MXID="@${USERNAME}:${SERVER_NAME}"

response=$(curl -sf -X PUT \
  "${HOMESERVER}/_matrix/client/v3/admin/users/${MXID}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"${PASSWORD}\", \"admin\": false}")

echo "Created account:"
echo "  MXID:     ${MXID}"
echo "  Password: ${PASSWORD}"
echo "  Server:   ${HOMESERVER}"
