#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$BASE_DIR/lib/common.sh"
fail=0
for service in xray mihomo nginx; do service_is_active "$service" && say "[OK] $service running" || say "[INFO] $service not running"; done
[[ -f "$NODE_FILE" ]] && say "[OK] node data present" || { say "[FAIL] node data missing"; fail=1; }
[[ -f "$WEB_ROOT/config.yaml" ]] && say "[OK] subscription config present" || say "[INFO] subscription config not generated"
if command -v xray >/dev/null && [[ -f "$XRAY_CONFIG" ]]; then xray run -test -c "$XRAY_CONFIG" >/dev/null && say "[OK] Xray config valid" || { say "[FAIL] Xray config invalid"; fail=1; }; fi
if command -v mihomo >/dev/null && [[ -f "$MIHOMO_CONFIG" ]]; then mihomo -t -f "$MIHOMO_CONFIG" >/dev/null && say "[OK] Mihomo config valid" || { say "[FAIL] Mihomo config invalid"; fail=1; }; fi
exit "$fail"
