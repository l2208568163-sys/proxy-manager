#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
case "${1:-}" in
  update) exec "$BASE_DIR/update.sh";; check) exec "$BASE_DIR/tests/check.sh";; version) cat "$BASE_DIR/VERSION"; exit;;
  --help|-h) echo "Usage: proxy [update|check|version]"; exit;; "") ;; *) die "Unknown command: $1";;
esac
require_root
while true; do
  clear; say "================================"; say " Proxy Manager v$(<"$BASE_DIR/VERSION")"; say "================================"
  say "1. Xray Reality"; say "2. Clash subscription"; say "3. Mihomo client"; say "4. DNS"; say "5. System optimisation"; say "6. Security"; say "7. Web subscription service"; say "8. Health check"; say "9. View node"; say "10. Update"; say "11. Uninstall"; say "0. Exit"
  read -r -p "Select: " c
  case "$c" in
    1) "$BASE_DIR/modules/xray.sh";;
    2) "$BASE_DIR/modules/subscription.sh";;
    3) "$BASE_DIR/modules/mihomo.sh";;
    4) "$BASE_DIR/modules/dns.sh";;
    5) "$BASE_DIR/modules/system.sh";;
    6) "$BASE_DIR/modules/security.sh";;
    7) "$BASE_DIR/modules/web.sh";;
    8) "$BASE_DIR/tests/check.sh"; read -r -p "Press Enter..." _;;
    9) load_node_data; say "Subscription: ${SUBSCRIPTION_URL:-http://$SERVER/clash/config.yaml}"; say "$VLESS_URI"; read -r -p "Press Enter..." _;;
    10) "$BASE_DIR/update.sh"; read -r -p "Press Enter..." _;; 11) exec "$BASE_DIR/uninstall.sh";; 0) exit;; *) say "Invalid selection.";;
  esac
done
