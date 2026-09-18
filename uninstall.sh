#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
source "$BASE_DIR/lib/common.sh"
require_root; confirm "Remove Proxy Manager commands and services?" || exit 0
systemctl disable --now mihomo 2>/dev/null || true; rm -f /etc/systemd/system/mihomo.service /usr/local/bin/proxy; systemctl daemon-reload
if confirm "Also remove generated node data and web subscription?"; then rm -rf "$BASE_DIR/data" "$WEB_ROOT"; else say "Node data retained in $BASE_DIR/data."; fi
confirm "Remove installed project directory ($BASE_DIR)?" && rm -rf "$BASE_DIR"
say "Uninstall finished. Xray is retained; remove it separately from the Xray menu if required."
