#!/usr/bin/env bash
set -Eeuo pipefail
# 本脚本位于项目根目录，dirname 已是根（不要再拼 /..，否则会解析到上一级）
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
[[ -f "$BASE_DIR/lib/common.sh" ]] || { echo "错误: 未定位到项目根目录（解析为 $BASE_DIR），请从项目目录内运行。" >&2; exit 1; }
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
require_root
git -C "$BASE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Installed project is not a Git checkout."
say "Current version: $(<"$BASE_DIR/VERSION")"
# install.sh 会给所有 .sh 加执行位；若 git 跟踪了 100644，每次 chmod 都会让工作树变脏，
# 导致 git pull --ff-only 永远报 "local changes would be overwritten"。忽略文件模式差异。
git -C "$BASE_DIR" config core.fileMode false
git -C "$BASE_DIR" fetch --prune origin
if ! git -C "$BASE_DIR" pull --ff-only origin main; then
  say "⚠ git pull 失败：本地存在未提交改动或分支已分叉。"
  say "  查看: git -C $BASE_DIR status"
  say "  放弃本地改动后重试: git -C $BASE_DIR checkout -- . && proxy update"
  die "更新中止（未做任何服务重启）。"
fi
find "$BASE_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
systemctl daemon-reload
restart_if_active xray; restart_if_active nginx
# 面板已安装过才刷新：requirements.txt 可能变化（如 python-multipart 补包）、
# systemd 单元可能调整；panel.sh install 幂等，沿用已有凭据不会重置密码
if [[ -f /etc/systemd/system/proxy-web.service ]]; then
  say "刷新 Web 管理面板（依赖 + systemd 单元）..."
  if bash "$BASE_DIR/modules/panel.sh" install; then
    restart_if_active proxy-web
    say "Web 面板已刷新。"
  else
    # 跨版本升级时，正在执行的可能是旧版 update.sh（引用的模块文件名可能已变，
    # 例如 v3.3.0 把 webpanel.sh 更名 panel.sh）。此时文件已在 pull 中就位，
    # 重跑一次即可用新版脚本完成刷新。
    say "⚠ Web 面板刷新失败。若本次为跨版本升级，请再运行一次 proxy update 完成刷新；"
    say "  或直接执行: proxy → 3（Web 管理中心）→ 1"
  fi
fi
say "Update completed. Current version: $(<"$BASE_DIR/VERSION")"
