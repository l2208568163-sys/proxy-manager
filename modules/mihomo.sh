#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_mihomo() {
  local platform asset tmp
  case "$(uname -m)" in x86_64|amd64) platform=amd64;; aarch64|arm64) platform=arm64;; armv7l|armv7) platform=armv7;; *) die "Unsupported CPU architecture.";; esac
  asset="$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | jq -r --arg p "mihomo-linux-$platform" '.assets[] | select(.name | startswith($p)) | select(.name | endswith(".gz")) | .browser_download_url' | head -n1)"
  [[ -n "$asset" && "$asset" != null ]] || die "No Mihomo release asset was found."
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN; curl -fL "$asset" | gzip -dc >"$tmp"; install -m 0755 "$tmp" /usr/local/bin/mihomo
  install -d -m 0755 "$MIHOMO_DIR"
  cat >/etc/systemd/system/mihomo.service <<'EOF'
[Unit]
Description=Mihomo Proxy Client
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; say "Mihomo 已安装。启动前请先导入订阅。"
}
import_config() {
  local url tmp; read -r -p "请输入 Mihomo 订阅 URL: " url; [[ "$url" =~ ^https?:// ]] || die "订阅地址必须以 http:// 或 https:// 开头"
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN; curl -fsSL --max-time 30 "$url" -o "$tmp"; mihomo -t -f "$tmp" >/dev/null
  install -d -m 0755 "$MIHOMO_DIR"; install -m 0600 "$tmp" "$MIHOMO_CONFIG"; systemctl enable --now mihomo; say "Mihomo 已启动。"
}
enable_tun() {
  [[ -f "$MIHOMO_CONFIG" ]] || die "Import a subscription before enabling TUN."
  grep -Eq '^tun:' "$MIHOMO_CONFIG" && die "该配置已定义 TUN，请直接编辑原配置，不要重复添加 TUN 段。"
  cat >>"$MIHOMO_CONFIG" <<'EOF'

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  dns-hijack:
    - any:53
    - tcp://any:53
EOF
  mihomo -t -f "$MIHOMO_CONFIG" >/dev/null
  systemctl restart mihomo
  say "TUN 模式已启用。它会修改主机路由表；如需关闭，请恢复原订阅配置。"
}
require_root
while true; do clear; say "===== Mihomo 客户端 ====="; say "1. 安装或更新核心"; say "2. 导入订阅并启动"; say "3. 为已导入配置启用 TUN 模式"; say "4. 重启"; say "5. 状态"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) install_mihomo; read -r -p "请按回车继续..." _;;2) require_command mihomo; import_config; read -r -p "请按回车继续..." _;;3) require_command mihomo; enable_tun; read -r -p "请按回车继续..." _;;4) systemctl restart mihomo;;5) systemctl --no-pager status mihomo || true; read -r -p "请按回车继续..." _;;0) exit;;*) say "无效选择。";;esac; done
