#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
source "$BASE_DIR/lib/common.sh"
fail=0
# shellcheck disable=SC2015
for service in xray nginx proxy-web; do service_is_active "$service" && say "[OK] $service running" || say "[INFO] $service not running"; done
# shellcheck disable=SC2015
[[ -f "$NODE_FILE" ]] && say "[OK] node data present" || { say "[FAIL] node data missing"; fail=1; }
# 订阅现位于 $WEB_ROOT/<随机令牌>/config.yaml（路径不可猜测）
# shellcheck disable=SC2015
[[ -n "$(find "$WEB_ROOT" -mindepth 2 -maxdepth 2 -name config.yaml -print -quit 2>/dev/null)" ]] && say "[OK] subscription config present" || say "[INFO] subscription config not generated"
# shellcheck disable=SC2015
if command -v xray >/dev/null && [[ -f "$XRAY_CONFIG" ]]; then xray run -test -c "$XRAY_CONFIG" >/dev/null && say "[OK] Xray config valid" || { say "[FAIL] Xray config invalid"; fail=1; }; fi
exit "$fail"
