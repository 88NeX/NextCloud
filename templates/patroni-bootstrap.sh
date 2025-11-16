#!/usr/bin/env bash
set -euo pipefail

NODE_ID="${1:-}"
HOST_IP="${2:-}"

if [[ -z "$NODE_ID" || -z "$HOST_IP" ]]; then
  echo "Usage: $0 <node-id> <host-ip>"
  exit 1
fi

TEMPLATE_PATH="/etc/patroni.yml.template"
DEST_PATH="/etc/patroni.yml"
TMP_PATH="${DEST_PATH}.tmp.$(date +%s)"

replace_placeholders() {
  local input="$1" output="$2"
  sed -e "s/{{NODE_ID}}/${NODE_ID}/g" -e "s/{{HOST_IP}}/${HOST_IP}/g" "$input" > "$output"
}

if [[ -f "$TEMPLATE_PATH" ]]; then
  replace_placeholders "$TEMPLATE_PATH" "$TMP_PATH"
  mv "$TMP_PATH" "$DEST_PATH"
  chmod 640 "$DEST_PATH" || true
elif [[ -f "$DEST_PATH" ]]; then
  replace_placeholders "$DEST_PATH" "$TMP_PATH"
  mv "$TMP_PATH" "$DEST_PATH"
else
  echo "No template ($TEMPLATE_PATH) or existing $DEST_PATH found to configure"
  exit 1
fi

# reload and start Patroni service if systemd present
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl enable --now patroni || {
    echo "Failed to enable/start patroni via systemctl; check service name and logs"
  }
else
  echo "systemctl not found; ensure patroni is started by other means"
fi
