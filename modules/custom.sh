#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

VLESS_URI_FILE="$NODE_FILE"

# 按当前 node.env 重建 vless:// 链接（端口/SNI/节点名变更后必须同步，否则面板与
# v2rayN 里显示的还是旧参数）
rebuild_vless_uri() {
  load_node_data || return 1
  local name="${NODE_NAME:-Reality-$SERVER}"
  local uri="vless://${UUID}@${SERVER}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${name}"
  env_upsert "$VLESS_URI_FILE" VLESS_URI "$uri"
}

show_params() {
  load_node_data || return 1
  local kind subj days
  IFS='|' read -r kind subj _ days <<<"$(cert_summary)"
  say "────────────────────────────────────────"
  printf '  %-16s %s\n' "服务器 IP"   "${SERVER}"
  printf '  %-16s %s\n' "主力端口"   "${PORT}/tcp (VLESS+Vision+REALITY)"
  printf '  %-16s %s\n' "伪装域名 SNI" "${SNI}"
  printf '  %-16s %s\n' "REALITY 目标" "${REALITY_DEST:-127.0.0.1:8443}"
  printf '  %-16s %s\n' "节点名称"   "${NODE_NAME:-Reality-$SERVER}"
  if [[ "${HY2:-0}" == "1" ]]; then
    printf '  %-16s %s\n' "Hysteria2" "UDP ${HY2_PORT} / 跳跃 ${HY2_HOP}"
  else
    printf '  %-16s %s\n' "Hysteria2" "未启用"
  fi
  printf '  %-16s %s (%s，剩余 %s 天)\n' "当前证书" "${subj:-无}" "${kind}" "${days}"
  local tok="${SUB_TOKEN:-}"
  printf '  %-16s %s\n' "订阅令牌"   "${tok:0:8}…（完整值见订阅页）"
  say "────────────────────────────────────────"
}

set_port() {
  load_node_data || return 1
  local p
  read -r -p "新的主力端口 [1-65535，当前 ${PORT}]: " p
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )) || { say "✗ 端口必须是 1-65535 的整数。"; return 1; }
  if [[ "$p" == "$PORT" ]]; then say "端口未变化。"; return 0; fi
  if port_in_use "$p" && ! ss -lntp 2>/dev/null | grep -w "$p" | grep -qi xray; then
    say "✗ 端口 ${p} 已被占用："; ss -lntp 2>/dev/null | grep -w "$p" || true
    return 1
  fi
  env_upsert "$NODE_FILE" PORT "$p"
  rebuild_vless_uri
  say "✓ 主力端口已改为 ${p}（选 9 应用后生效；客户端需更新订阅）"
}

set_sni() {
  load_node_data || return 1
  local d
  say "SNI 必须是域名（REALITY 不接受 IP）；修改后需确保证书覆盖该域名。"
  read -r -p "新的伪装域名 [当前 ${SNI}]: " d
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]] \
    || { say "✗ 域名格式不正确（示例：www.example.com）。"; return 1; }
  env_upsert "$NODE_FILE" SNI "$d"
  env_upsert "$NODE_FILE" CAMO_DOMAIN "$d"
  if [[ "${HY2:-0}" == "1" ]]; then env_upsert "$NODE_FILE" HY2_SNI "$d"; fi
  rebuild_vless_uri
  say "✓ 伪装域名已改为 ${d}（建议接着用主菜单 4 重新签发证书，再选 9 应用）"
}

set_node_name() {
  load_node_data || return 1
  local n
  read -r -p "新的节点名称 [当前 ${NODE_NAME:-Reality-$SERVER}]: " n
  [[ -n "$n" ]] || { say "✗ 名称不能为空。"; return 1; }
  [[ "$n" =~ ^[A-Za-z0-9._-]+$ ]] || { say "✗ 名称只允许字母数字与 . _ -（避免 YAML/URI 转义问题）。"; return 1; }
  env_upsert "$NODE_FILE" NODE_NAME "$n"
  rebuild_vless_uri
  say "✓ 节点名称已改为 ${n}"
}

set_dest() {
  load_node_data || return 1
  local d
  say "REALITY dest 是未认证流量的转发目标，默认指向本机伪装站 127.0.0.1:8443。"
  read -r -p "新的 dest [host:port，当前 ${REALITY_DEST:-127.0.0.1:8443}]: " d
  [[ "$d" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]] || { say "✗ 格式应为 host:port。"; return 1; }
  env_upsert "$NODE_FILE" REALITY_DEST "$d"
  say "✓ dest 已改为 ${d}"
}

set_hy2() {
  load_node_data || return 1
  if [[ "${HY2:-0}" != "1" ]]; then
    say "当前未启用 Hysteria2。请先在主菜单 2 安装备用链路。"
    return 1
  fi
  local p h
  read -r -p "Hysteria2 UDP 端口 [当前 ${HY2_PORT}]: " p
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )) || { say "✗ 端口非法。"; return 1; }
  read -r -p "端口跳跃范围 [起-止，当前 ${HY2_HOP}]: " h
  [[ "$h" =~ ^[0-9]+-[0-9]+$ ]] || { say "✗ 格式应为 20000-40000。"; return 1; }
  local lo="${h%-*}" hi="${h#*-}"
  (( lo < hi && lo >= 1 && hi <= 65535 )) || { say "✗ 范围非法（起始需小于结束且都在 1-65535）。"; return 1; }
  env_upsert "$NODE_FILE" HY2_PORT "$p"
  env_upsert "$NODE_FILE" HY2_HOP "$h"
  say "✓ Hysteria2 参数已更新（需重跑主菜单 2 的安装以重建服务与 nat 规则）"
}

regen_token() {
  load_node_data || return 1
  say "⚠ 重新生成令牌后，旧订阅地址立即失效，所有客户端需重新导入。"
  confirm "确认重新生成订阅令牌？" || { say "已取消。"; return 0; }
  local t
  t="$(openssl rand -hex 16)"
  env_upsert "$NODE_FILE" SUB_TOKEN "$t"
  env_upsert "$NODE_FILE" SUBSCRIPTION_URL "http://${SERVER}/clash/${t}/config.yaml"
  say "✓ 新令牌已生成（选 9 应用并重建订阅后生效）"
}

edit_raw() {
  local ed="${EDITOR:-}"
  if [[ -z "$ed" ]]; then
    if command -v nano >/dev/null 2>&1; then ed="nano"
    elif command -v vim >/dev/null 2>&1; then ed="vim"
    elif command -v vi >/dev/null 2>&1; then ed="vi"
    else say "✗ 系统没有可用的编辑器（nano/vim/vi）。"; return 1; fi
  fi
  cp -a "$NODE_FILE" "${NODE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  say "已备份到 ${NODE_FILE}.bak.*，编辑保存后请选 9 应用。"
  "$ed" "$NODE_FILE"
}

backup_config() {
  local dir
  dir="/opt/proxy-config-backup-$(date +%Y%m%d-%H%M%S)"
  install -d -m 0700 "$dir"
  cp -a "$NODE_FILE" "$dir/" 2>/dev/null || true
  [[ -f /usr/local/etc/xray/config.json ]] && cp -a /usr/local/etc/xray/config.json "$dir/" 2>/dev/null || true
  [[ -f /etc/hysteria/config.yaml ]] && cp -a /etc/hysteria/config.yaml "$dir/" 2>/dev/null || true
  [[ -f /etc/ssl/certs/camo.crt ]] && cp -a /etc/ssl/certs/camo.crt /etc/ssl/private/camo.key "$dir/" 2>/dev/null || true
  say "✓ 已备份到 ${dir}"
}

restore_config() {
  local dirs=()
  while IFS= read -r d; do dirs+=("$d"); done < <(find /opt -maxdepth 1 -type d -name 'proxy-config-backup-*' 2>/dev/null | sort -r)
  ((${#dirs[@]})) || { say "没有找到配置备份。"; return 1; }
  local i=1 d
  for d in "${dirs[@]}"; do say "  ${i}) $(basename "$d")"; i=$((i+1)); done
  local c
  read -r -p "选择要恢复的备份编号（0 取消）: " c
  [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#dirs[@]} )) || { say "已取消。"; return 0; }
  d="${dirs[$((c-1))]}"
  confirm "确认用 $(basename "$d") 覆盖当前配置？" || { say "已取消。"; return 0; }
  [[ -f "$d/node.env" ]] && install -m 0600 "$d/node.env" "$NODE_FILE"
  [[ -f "$d/config.json" ]] && install -m 0644 "$d/config.json" /usr/local/etc/xray/config.json
  [[ -f "$d/config.yaml" ]] && install -m 0600 "$d/config.yaml" /etc/hysteria/config.yaml
  [[ -f "$d/camo.crt" ]] && install -m 0644 "$d/camo.crt" /etc/ssl/certs/camo.crt
  [[ -f "$d/camo.key" ]] && install -m 0600 "$d/camo.key" /etc/ssl/private/camo.key
  say "✓ 已恢复，选 9 应用使配置生效。"
}

apply_all() {
  load_node_data || return 1
  say "正在应用配置（重写 Xray 配置并重启）..."
  rewrite_xray_config || return 1
  say "正在重建订阅..."
  "$SCRIPT_DIR/subscription.sh" generate || { say "✗ 订阅重建失败。"; return 1; }
  local kind subj days
  IFS='|' read -r kind subj _ days <<<"$(cert_summary)"
  say "────────────────────────────────────────"
  say "✓ 配置已应用"
  say "  节点: $(grep '^VLESS_URI=' "$NODE_FILE" | cut -d= -f2- | tr -d '\"')"
  say "  订阅: $(grep '^SUBSCRIPTION_URL=' "$NODE_FILE" | cut -d= -f2-)"
  say "  证书: ${subj}（${kind}，剩余 ${days} 天）"
  say "  ⚠ 客户端需要「更新订阅」才能拿到新参数"
}

require_root
while true; do
  clr
  say "===== 自定义配置 ====="
  show_params || true
  say "1. 修改主力端口"
  say "2. 修改伪装域名（SNI）"
  say "3. 修改节点名称"
  say "4. 修改 REALITY 转发目标（dest）"
  say "5. 修改 Hysteria2 端口 / 跳跃范围"
  say "6. 重新生成订阅令牌"
  say "7. 高级：直接编辑 node.env"
  say "8. 备份 / 恢复配置"
  say "9. 应用配置（重启 Xray + 重建订阅）"
  say "0. 返回"
  read -r -p "请选择: " c || exit 0
  case "$c" in
    1) if ! set_port; then :; fi; read -r -p "请按回车继续..." _ || true;;
    2) if ! set_sni; then :; fi; read -r -p "请按回车继续..." _ || true;;
    3) if ! set_node_name; then :; fi; read -r -p "请按回车继续..." _ || true;;
    4) if ! set_dest; then :; fi; read -r -p "请按回车继续..." _ || true;;
    5) if ! set_hy2; then :; fi; read -r -p "请按回车继续..." _ || true;;
    6) if ! regen_token; then :; fi; read -r -p "请按回车继续..." _ || true;;
    7) if ! edit_raw; then :; fi; read -r -p "请按回车继续..." _ || true;;
    8) clr; say "1) 备份当前配置"; say "2) 从备份恢复"; read -r -p "请选择: " b
       case "$b" in
         1) backup_config;; 2) if ! restore_config; then :; fi;;
         *) say "无效选择。";;
       esac
       read -r -p "请按回车继续..." _ || true;;
    9) if ! apply_all; then :; fi; read -r -p "请按回车继续..." _ || true;;
    0) exit;;
    *) say "无效选择。";;
  esac
done
