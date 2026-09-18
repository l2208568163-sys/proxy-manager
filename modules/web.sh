#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_web() { install -d -m 0755 "$WEB_ROOT"; systemctl enable --now nginx; [[ -f "$WEB_ROOT/config.yaml" ]] || "$SCRIPT_DIR/subscription.sh" generate; command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow 80/tcp || true; load_node_data; say "Published: $SUBSCRIPTION_URL"; }
require_root
while true; do clear; say "===== Web Subscription Service ====="; say "1. Enable Nginx and publish config"; say "2. Status"; say "0. Back"; read -r -p "Select: " c; case "$c" in 1) install_web; read -r -p "Press Enter..." _;;2) systemctl --no-pager status nginx || true; read -r -p "Press Enter..." _;;0) exit;;*) say "Invalid selection.";;esac; done
