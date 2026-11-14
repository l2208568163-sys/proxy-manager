#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

CERT_FILE="/etc/ssl/certs/camo.crt"
KEY_FILE="/etc/ssl/private/camo.key"
ACME_BIN="/root/.acme.sh/acme.sh"
WEBROOT="/var/www/html"

show_status() {
  local kind subj end days
  IFS='|' read -r kind subj end days <<<"$(cert_summary "$CERT_FILE")"
  say "────────────────────────────────────────"
  if [[ "$kind" == "none" ]]; then
    say "  证书：未安装"
  else
    say "  证书主体：${subj}"
    say "  签发机构：${kind}"
    say "  到期时间：${end}（剩余 ${days} 天）"
  fi
  if [[ -x "$ACME_BIN" ]]; then
    say "  acme.sh ：已安装（自动续期 cron 由 acme.sh 维护）"
    "$ACME_BIN" --list 2>/dev/null | sed -n '1,6p' | sed 's/^/    /' || true
  else
    say "  acme.sh ：未安装（仅支持当前证书，无法自动续期）"
  fi
  say "────────────────────────────────────────"
}

# DNS 解析检查：域名必须能解析，否则 HTTP-01 一定失败（走 CDN 时解析值与本机不同属正常）
check_dns() {
  local d="$1" ip pub
  ip="$(getent ahostsv4 "$d" 2>/dev/null | awk 'NR==1{print $1}')"
  pub="$(detect_public_ip 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    say "✗ 域名 ${d} 无法解析，请先添加 A 记录指向本机公网 IP。"
    return 1
  fi
  say "  域名解析 → ${ip}"
  say "  本机公网 → ${pub:-未知}"
  if [[ -n "$pub" && "$ip" != "$pub" ]]; then
    say "⚠ 解析地址与本机公网不一致：若使用 CDN 可继续（需回源到本机 80），否则证书申请会失败。"
  else
    say "✓ 解析正确"
  fi
  return 0
}

# HTTP-01 连通性自检：写探针文件后从公网回读（这一步能提前暴露 80 未放行/nginx 未运行）
check_http01() {
  local d="$1" probe code
  install -d -m 0755 "${WEBROOT}/.well-known/acme-challenge"
  probe="pm-$(openssl rand -hex 6)"
  printf '%s\n' "$probe" >"${WEBROOT}/.well-known/acme-challenge/${probe}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://${d}/.well-known/acme-challenge/${probe}" || true)"
  rm -f "${WEBROOT}/.well-known/acme-challenge/${probe}"
  if [[ "$code" == "200" ]]; then
    say "✓ HTTP-01 通道正常（80 端口公网可达）"
    return 0
  fi
  say "✗ HTTP-01 自检失败（HTTP ${code:-无响应}）"
  say "  常见原因：① 安全组未放行 TCP 80  ② nginx 未运行  ③ 域名解析未生效"
  return 1
}

install_acme() {
  local d="$1"
  [[ -x "$ACME_BIN" ]] && { say "✓ acme.sh 已安装"; return 0; }
  say "安装 acme.sh ..."
  curl -fsSL --max-time 60 https://get.acme.sh | sh -s email="admin@${d}" >/dev/null 2>&1 || {
    say "✗ acme.sh 安装失败（无法访问 get.acme.sh，请检查 VPS 出网）"
    return 1
  }
  [[ -x "$ACME_BIN" ]] || { say "✗ acme.sh 安装后未找到 ${ACME_BIN}"; return 1; }
  say "✓ acme.sh 安装完成（会自动创建续期 cron）"
}

# 绑定域名 → 申请证书 → 安装证书 → 更新 node.env → 重写 Xray 配置 → 重建订阅
bind_domain() {
  load_node_data || return 1
  local d
  say "说明：证书用于 ① nginx 伪装站（REALITY dest）② Hysteria2 TLS。"
  say "      HTTP-01 验证需要域名解析到本机、且 TCP 80 公网可达。"
  read -r -p "要绑定的域名（如 proxy.example.com）: " d
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]] \
    || { say "✗ 域名格式不正确。"; return 1; }

  check_dns "$d" || { confirm "解析异常，仍要继续尝试？" || { say "已取消。"; return 0; }; }
  check_http01 "$d" || { confirm "80 自检未通过，仍要继续尝试？" || { say "已取消。"; return 0; }; }
  install_acme "$d" || return 1

  say "正在向 Let's Encrypt 申请证书（HTTP-01）..."
  local out
  if ! out="$("$ACME_BIN" --issue -d "$d" -w "$WEBROOT" --server letsencrypt 2>&1)"; then
    say "✗ 证书签发失败，已保留原证书（站点不会中断）。acme.sh 输出："
    printf '%s\n' "$out" | tail -12 | sed 's/^/    /'
    say "  常见原因："
    say "   1) 域名未解析到本机 / DNS 未生效（用主菜单 5 检查）"
    say "   2) 安全组未放行 TCP 80"
    say "   3) 该域名本周签发次数超限（Let's Encrypt 限制：同一域名 5 次/周）"
    say "   4) 域名已配置 CAA 记录禁止 Let's Encrypt"
    return 1
  fi
  say "✓ 证书签发成功"

  say "正在安装证书到 ${CERT_FILE} 并配置自动续期钩子..."
  if ! "$ACME_BIN" --install-cert -d "$d" \
      --key-file "$KEY_FILE" \
      --fullchain-file "$CERT_FILE" \
      --reloadcmd "systemctl reload nginx >/dev/null 2>&1 || true; systemctl restart hysteria-server >/dev/null 2>&1 || true" 2>&1 | tail -5; then
    say "✗ 证书安装失败（签发成功但写入失败），请检查 ${CERT_FILE} 权限。"
    return 1
  fi

  # 更新配置：SNI 与 Hysteria2 的 sni 都切到新域名
  env_upsert "$NODE_FILE" SNI "$d"
  env_upsert "$NODE_FILE" CAMO_DOMAIN "$d"
  env_upsert "$NODE_FILE" CERT_DOMAIN "$d"
  env_upsert "$NODE_FILE" CERT_MODE "acme"
  if [[ "${HY2:-0}" == "1" ]]; then env_upsert "$NODE_FILE" HY2_SNI "$d"; fi

  say "正在重写 Xray 配置并重启（serverNames → ${d}）..."
  rewrite_xray_config || { say "✗ Xray 重载失败，证书已就位但配置未生效。"; return 1; }
  "$SCRIPT_DIR/subscription.sh" generate >/dev/null 2>&1 && say "✓ 订阅已重建" || say "⚠ 订阅重建失败，请在主菜单 6 手动重试"

  say ""
  say "✓ 域名绑定完成"
  show_status
  say "⚠ 客户端需更新订阅（SNI 已变更为 ${d}）"
}

renew_cert() {
  local dom
  dom="$(grep '^CERT_DOMAIN=' "$NODE_FILE" 2>/dev/null | cut -d= -f2- || true)"
  [[ -n "$dom" ]] || { say "尚未绑定域名（当前为自签证书），无需续期。"; return 1; }
  [[ -x "$ACME_BIN" ]] || { say "✗ 未找到 acme.sh。"; return 1; }
  say "强制续期 ${dom} ..."
  if "$ACME_BIN" --renew -d "$dom" --force 2>&1 | tail -8; then
    show_status
  else
    say "✗ 续期失败（证书到期前 30 天自动续期通常无需手动操作）。"
    return 1
  fi
}

restore_selfsigned() {
  load_node_data || return 1
  local d="${SNI:-www.local-cloud.net}"
  confirm "确认放弃域名证书，恢复自签证书（SNI=${d}）？" || { say "已取消。"; return 0; }
  install -d -m 0755 /etc/ssl/private
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/C=US/ST=California/L=San Jose/O=Local Cloud Networks/CN=${d}" \
    -addext "subjectAltName=DNS:${d}" >/dev/null 2>&1 || { say "✗ 自签证书生成失败。"; return 1; }
  chmod 600 "$KEY_FILE"
  env_upsert "$NODE_FILE" CERT_MODE "self"
  systemctl reload nginx 2>/dev/null || true
  systemctl restart hysteria-server 2>/dev/null || true
  say "✓ 已恢复自签证书（acme.sh 的续期 cron 仍在，可忽略或手动删除）"
  show_status
}

require_root
while true; do
  clr
  say "===== 域名绑定与证书 ====="
  show_status
  say "1. 绑定域名并自动签发证书（Let's Encrypt · HTTP-01）"
  say "2. 查看证书详情 / 续期状态"
  say "3. 强制续期"
  say "4. 检查域名解析"
  say "5. 恢复自签证书"
  say "0. 返回"
  read -r -p "请选择: " c || exit 0
  case "$c" in
    1) if ! bind_domain; then :; fi; read -r -p "请按回车继续..." _ || true;;
    2) show_status; read -r -p "请按回车继续..." _ || true;;
    3) if ! renew_cert; then :; fi; read -r -p "请按回车继续..." _ || true;;
    4) read -r -p "域名: " d; clr; check_dns "$d" || true; read -r -p "请按回车继续..." _ || true;;
    5) if ! restore_selfsigned; then :; fi; read -r -p "请按回车继续..." _ || true;;
    0) exit;;
    *) say "无效选择。";;
  esac
done
