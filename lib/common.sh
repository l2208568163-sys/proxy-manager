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
restart_if_active() { service_is_active "$1" && { systemctl restart "$1"; say "Restarted $1."; }; }
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

port_in_use() { ss -ltn 2>/dev/null | awk -v p="$1" '$4 ~ (":" p "$") { found=1 } END { exit !found }'; }
choose_available_port() { local p; for p in 443 8443 2053 2083; do port_in_use "$p" || { echo "$p"; return; }; done; return 1; }
detect_public_ip() {
  local url ip
  for url in https://api.ipify.org https://ifconfig.me/ip https://ipv4.icanhazip.com; do
    ip="$(curl -4fsSL --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)"; ip="${ip//$'\n'/}"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return; }
  done
  return 1
}
