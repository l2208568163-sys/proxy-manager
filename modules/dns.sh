#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
configure_resolved() { install -d -m 0755 /etc/systemd/resolved.conf.d; cat >/etc/systemd/resolved.conf.d/proxy-manager.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 8.8.4.4
DNSOverTLS=opportunistic
EOF
systemctl restart systemd-resolved; say "系统 DNS 已配置。"; }
install_adguard_home() {
  local arch url tmp ip
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; armv7l|armv7) arch=armv7;; *) die "Unsupported CPU architecture.";; esac
  [[ ! -e /opt/AdGuardHome ]] || die "AdGuard Home already exists at /opt/AdGuardHome."
  url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${arch}.tar.gz"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  curl -fL "$url" -o "$tmp/adguard.tar.gz"; tar -xzf "$tmp/adguard.tar.gz" -C /opt
  /opt/AdGuardHome/AdGuardHome -s install
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && { ufw allow 3000/tcp; ufw allow 53/udp; } || true
  ip="$(detect_public_ip || echo '<server-ip>')"
  say "AdGuard Home 已安装。请访问 http://$ip:3000 完成初始化设置"
}
require_root
while true; do clear; say "===== DNS 管理 ====="; say "1. 配置 Cloudflare DNS（含 DoT）"; say "2. 安装 AdGuard Home"; say "3. 查看解析器状态"; say "4. 移除 Proxy Manager 的 DNS 覆盖"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) configure_resolved; read -r -p "请按回车继续..." _;;2) install_adguard_home; read -r -p "请按回车继续..." _;;3) resolvectl status 2>/dev/null || cat /etc/resolv.conf; read -r -p "请按回车继续..." _;;4) confirm "确认移除 DNS 覆盖配置？" && { rm -f /etc/systemd/resolved.conf.d/proxy-manager.conf; systemctl restart systemd-resolved; };;0) exit;;*) say "无效选择。";;esac; done
