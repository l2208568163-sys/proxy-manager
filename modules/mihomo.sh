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
  systemctl daemon-reload; say "Mihomo installed. Import a subscription before starting it."
}
import_config() {
  local url tmp; read -r -p "Mihomo subscription URL: " url; [[ "$url" =~ ^https?:// ]] || die "URL must begin with http:// or https://"
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN; curl -fsSL --max-time 30 "$url" -o "$tmp"; mihomo -t -f "$tmp" >/dev/null
  install -d -m 0755 "$MIHOMO_DIR"; install -m 0600 "$tmp" "$MIHOMO_CONFIG"; systemctl enable --now mihomo; say "Mihomo started."
}
enable_tun() {
  [[ -f "$MIHOMO_CONFIG" ]] || die "Import a subscription before enabling TUN."
  grep -Eq '^tun:' "$MIHOMO_CONFIG" && die "This profile already defines TUN. Edit it directly instead of adding a second TUN section."
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
  say "TUN mode enabled. It changes the host routing table; disable it by restoring the subscription profile if required."
}
require_root
while true; do clear; say "===== Mihomo Client ====="; say "1. Install or update core"; say "2. Import subscription and start"; say "3. Enable TUN mode for imported profile"; say "4. Restart"; say "5. Status"; say "0. Back"; read -r -p "Select: " c; case "$c" in 1) install_mihomo; read -r -p "Press Enter..." _;;2) require_command mihomo; import_config; read -r -p "Press Enter..." _;;3) require_command mihomo; enable_tun; read -r -p "Press Enter..." _;;4) systemctl restart mihomo;;5) systemctl --no-pager status mihomo || true; read -r -p "Press Enter..." _;;0) exit;;*) say "Invalid selection.";;esac; done
