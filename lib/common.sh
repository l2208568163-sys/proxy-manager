#!/usr/bin/env bash

BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA_DIR="$BASE_DIR/data"
NODE_FILE="$DATA_DIR/node.env"
WEB_ROOT="${WEB_ROOT:-/var/www/html/clash}"
XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
MIHOMO_CONFIG="$MIHOMO_DIR/config.yaml"

say() { printf '%s\n' "$*"; }
die() { say "错误: $*" >&2; exit 1; }
require_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请使用 root 权限运行。"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
service_is_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
# 只在服务运行时重启；服务未运行视为「无需处理」，必须返回 0，
# 否则调用方在 set -e 下会因为「服务没装/没跑」而中断整条流程。
restart_if_active() {
  service_is_active "$1" || return 0
  if systemctl restart "$1" 2>/dev/null; then
    say "Restarted $1."
  else
    say "⚠ 重启 $1 失败（服务可能启动异常，请运行 systemctl status $1 查看）。"
  fi
  return 0
}
confirm() { local a; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]([Ee][Ss])?$ ]]; }

load_node_data() {
  [[ -f "$NODE_FILE" ]] || die "未找到节点信息，请先安装 Xray Reality。"
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  local key
  for key in SERVER UUID PUBLIC_KEY SHORT_ID PORT SNI; do
    [[ -n "${!key:-}" ]] || die "节点数据不完整：$key 缺失。"
  done
}

# 在 env 文件中更新或追加 KEY=VALUE。
# 用 awk + ENVIRON 重写整行，而不是 sed 替换：值里可能出现 & | \ 等字符
# （例如含 & 的 VLESS_URI），sed 会把 & 展开成整段匹配、把 | 当成分隔符，
# 导致密钥/URL 被静默写坏。
env_upsert() {
  local f="$1" k="$2" v="$3" tmp
  [[ -f "$f" ]] || install -m 0600 /dev/null "$f"
  tmp="$(mktemp)"
  K="$k" V="$v" awk '
    BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"]; done = 0 }
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$f" >"$tmp" && mv "$tmp" "$f"
  rm -f "$tmp"
  chmod 0600 "$f"
}
port_in_use() { ss -ltn 2>/dev/null | awk -v p="$1" '$4 ~ (":" p "$") { found=1 } END { exit !found }'; }
choose_available_port() { local p; for p in 443 8443 2053 2083; do port_in_use "$p" || { echo "$p"; return; }; done; return 1; }
# 等待端口进入监听，默认最多 5 秒（每 0.5s 探一次）；成功返回 0
wait_for_listen() { local p="$1" tries="${2:-10}" i=0; while (( i < tries )); do port_in_use "$p" && return 0; sleep 0.5; i=$((i+1)); done; return 1; }
detect_public_ip() {
  local url ip
  for url in https://api.ipify.org https://ifconfig.me/ip https://ipv4.icanhazip.com; do
    ip="$(curl -4fsSL --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)"; ip="${ip//$'\n'/}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return; }
  done
  return 1
}
