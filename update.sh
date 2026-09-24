#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
require_root
git -C "$BASE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Installed project is not a Git checkout."
say "Current version: $(<"$BASE_DIR/VERSION")"
git -C "$BASE_DIR" fetch --prune origin
git -C "$BASE_DIR" pull --ff-only origin main
find "$BASE_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
systemctl daemon-reload
restart_if_active xray; restart_if_active mihomo; restart_if_active nginx
# 面板已安装过才刷新：requirements.txt 可能变化（如 python-multipart 补包）、
# systemd 单元可能调整；webpanel.sh install 幂等，沿用已有凭据不会重置密码
if [[ -f /etc/systemd/system/proxy-web.service ]]; then
  say "刷新 Web 管理面板（依赖 + systemd 单元）..."
  if bash "$BASE_DIR/modules/webpanel.sh" install; then
    restart_if_active proxy-web
    say "Web 面板已刷新。"
  else
    say "⚠ Web 面板刷新失败，可稍后运行主菜单 12 → 1 重试。"
  fi
fi
say "Update completed. Current version: $(<"$BASE_DIR/VERSION")"
