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
  local key main_ok=1 wifi_ok=1
  for key in SERVER SNI; do
    [[ -n "${!key:-}" ]] || die "节点数据不完整：$key 缺失。"
  done
  # 主节点与 WiFi web 跳验证专属节点至少存在其一（WiFi 节点可独立于主节点部署）
  for key in UUID PUBLIC_KEY SHORT_ID PORT; do
    [[ -n "${!key:-}" ]] || main_ok=0
  done
  for key in WIFI_UUID WIFI_PUBLIC_KEY WIFI_SHORT_ID WIFI_PORT; do
    [[ -n "${!key:-}" ]] || wifi_ok=0
  done
  (( main_ok || wifi_ok )) || die "节点数据不完整：主节点与 WiFi 节点信息均缺失。"
}

# 在 env 文件中更新或追加 KEY=VALUE。
# 注意：sed 替换串里 & 会被展开为"整段匹配"、| 会提前截断替换、\ 需自转义，
# 故含 & 的值（如 VLESS/WiFi 节点的 URI 查询串）必须先转义，否则写进 node.env 会被写坏。
env_upsert() {
  local f="$1" k="$2" v="$3"
  [[ -f "$f" ]] || install -m 0600 /dev/null "$f"
  local ve="${v//\\/\\\\}"; ve="${ve//&/\\&}"; ve="${ve//|/\\|}"
  if grep -q "^${k}=" "$f"; then
    sed -i "s|^${k}=.*|${k}=${ve}|" "$f"
  else
    printf '%s=%s\n' "$k" "$v" >>"$f"
  fi
}
port_in_use() { ss -ltn 2>/dev/null | awk -v p="$1" '$4 ~ (":" p "$") { found=1 } END { exit !found }'; }
choose_available_port() { local p; for p in 443 8443 2053 2083; do port_in_use "$p" || { echo "$p"; return; }; done; return 1; }
# WiFi web 跳验证：优先选网关默认放行的端口（DNS/DHCP/NTP 等），用于绕过 captive portal
# 这些端口常被热点放行以便跳转到 Web 认证页；Xray 仍为 TCP 监听，配合订阅侧 fragment 分片抗浅层 SNI/DPI
choose_bypass_port() { local p; for p in 53 67 68 123; do port_in_use "$p" || { echo "$p"; return; }; done; return 1; }
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
