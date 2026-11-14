#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "$BASE_DIR/lib/common.sh"
case "${1:-}" in
  update) exec "$BASE_DIR/update.sh";; check) exec "$BASE_DIR/tests/check.sh";; version) cat "$BASE_DIR/VERSION"; exit;;
  --help|-h) echo "Usage: proxy [update|check|version]"; exit;; "") ;; *) die "Unknown command: $1";;
esac
require_root

pause() { read -r -p "请按回车继续..." _ || true; }
# 统一的子命令调用：任何非零退出都只提示、不带走菜单。
run_cmd() {
  local label="$1"; shift
  if ! "$@"; then
    say "（${label} 未成功完成，原因见上方输出）"
  fi
  pause
}

# ---- 顶部状态栏 ----
status_xray() {
  service_is_active xray || { printf '未运行'; return; }
  printf '运行中(:%s)' "${PORT:-?}"
}
status_hy2() {
  if [[ "${HY2:-0}" != "1" ]]; then printf '未启用'; return; fi
  service_is_active hysteria-server || { printf '未运行'; return; }
  printf '运行中(UDP:%s)' "${HY2_PORT:-?}"
}
status_cert() {
  local kind subj days
  IFS='|' read -r kind subj _ days <<<"$(cert_summary)"
  if [[ "$kind" == "none" ]]; then printf '无证书'; return; fi
  printf '%s · %s · %s 天' "$kind" "$subj" "$days"
}
status_panel() {
  if ! systemctl list-unit-files 2>/dev/null | grep -q '^proxy-web\.service'; then printf '未安装（默认关闭）'; return; fi
  if service_is_active proxy-web; then printf '运行中'; else printf '已安装未运行'; fi
}
load_quiet() { load_node_data >/dev/null 2>&1 || true; }
# 重建伪装站点：复用 modules/xray.sh 里的 install_camouflage_site，
# 通过「提取函数体到 modules/ 下的临时文件」调用（保持 SCRIPT_DIR 相对路径可解析）
rebuild_site() {
  local tmp="$BASE_DIR/modules/.rebuild_site.sh"
  sed '/^require_root$/,$d' "$BASE_DIR/modules/xray.sh" >"$tmp"
  # shellcheck disable=SC1090
  if ( source "$tmp" && install_camouflage_site ); then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

while true; do
  load_quiet
  clr
  say "════════════════════════════════════════════"
  say "  代理管理器 Proxy Manager v$(<"$BASE_DIR/VERSION")"
  say "════════════════════════════════════════════"
  printf '  链路  Xray:%s   Hysteria2:%s\n' "$(status_xray)" "$(status_hy2)"
  printf '  证书  %s\n' "$(status_cert)"
  printf '  站点  https://%s（本机 127.0.0.1:%s）\n' "${SNI:-—}" "${CAMO_HTTPS_PORT:-8443}"
  printf '  面板  %s\n' "$(status_panel)"
  say "────────────────────────────────────────────"
  say "【链路】"
  say "  1. 主力链路   VLESS+Vision+REALITY :${PORT:-443}"
  say "  2. 备用链路   Hysteria2 + 端口跳跃"
  say "  3. 伪装站点   重建本机 HTTPS 站点"
  say "【域名与证书】"
  say "  4. 域名绑定与证书（自动签发 / 续期 / 状态）"
  say "【订阅与节点】"
  say "  5. Clash 订阅生成 / 发布"
  say "  6. 查看全部节点信息"
  say "【高级】"
  say "  7. 自定义配置（端口 / 域名 / HY2 参数 / 备份恢复）"
  say "  8. 健康检查"
  say "  9. 更新程序"
  say " 10. Web 面板（默认关闭，需手动启用）"
  say " 11. 卸载 Proxy Manager"
  say "  0. 退出"
  say "────────────────────────────────────────────"
  read -r -p "请选择: " c || exit 0
  case "$c" in
    1) run_cmd "主力链路" "$BASE_DIR/modules/xray.sh";;
    2) run_cmd "备用链路" "$BASE_DIR/modules/xray.sh";;
    3) if ! rebuild_site; then say "（伪装站点重建失败，原因见上方输出）"; fi; pause;;
    4) run_cmd "域名与证书" "$BASE_DIR/modules/cert.sh";;
    5) run_cmd "Clash 订阅" "$BASE_DIR/modules/subscription.sh";;
    6) load_quiet
       say "────────────────────────────────────────"
       say "主力节点: ${VLESS_URI:-（未配置）}"
       if [[ "${HY2:-0}" == "1" ]]; then
         say "备用节点: Hysteria2  ${SERVER:-?}:${HY2_PORT}  UDP"
         say "         端口跳跃 ${HY2_HOP}   密码 ${HY2_PASSWORD}"
         say "         SNI ${HY2_SNI:-$SNI}   skip-cert-verify: true"
       fi
       say "订阅地址: ${SUBSCRIPTION_URL:-（尚未生成，请在 5 中生成）}"
       say "────────────────────────────────────────"
       pause;;
    7) run_cmd "自定义配置" "$BASE_DIR/modules/custom.sh";;
    8) run_cmd "健康检查" "$BASE_DIR/tests/check.sh";;
    9) run_cmd "更新程序" "$BASE_DIR/update.sh";;
    10) run_cmd "Web 面板" "$BASE_DIR/modules/panel.sh";;
    11) exec "$BASE_DIR/uninstall.sh";;
    0) exit;;
    *) say "无效选择。";;
  esac
done
