#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
SNI="${REALITY_SERVER_NAME:-www.cloudflare.com}"
key() { awk -F': *' -v n="$1" 'tolower($1)==tolower(n) {print $2; exit}' <<<"$2"; }
install_xray() {
  local port keys private public uuid short server
  port="$(choose_available_port)" || die "Ports 443, 8443, 2053 and 2083 are in use."
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  uuid="$(xray uuid)"; keys="$(xray x25519)"; private="$(key 'Private key' "$keys")"; public="$(key 'Public key' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || die "Unable to read Xray Reality keys."
  short="$(openssl rand -hex 8)"; server="$(detect_public_ip)" || die "Unable to detect public IPv4."
  install -d -m 0755 "$(dirname "$XRAY_CONFIG")" "$DATA_DIR"
  cat >"$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"0.0.0.0","port":$port,"protocol":"vless","settings":{"clients":[{"id":"$uuid","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"$SNI:443","xver":0,"serverNames":["$SNI"],"privateKey":"$private","shortIds":["$short"]}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
  xray run -test -c "$XRAY_CONFIG" >/dev/null
  umask 077; cat >"$NODE_FILE" <<EOF
SERVER=$server
PORT=$port
UUID=$uuid
PRIVATE_KEY=$private
PUBLIC_KEY=$public
SHORT_ID=$short
SNI=$SNI
NODE_NAME=Reality-$server
SUBSCRIPTION_URL=http://$server/clash/config.yaml
VLESS_URI="vless://$uuid@$server:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$public&sid=$short&type=tcp#Reality-$server"
EOF
  chmod 0600 "$NODE_FILE"; systemctl enable --now xray
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow "$port/tcp" || true
  "$SCRIPT_DIR/subscription.sh" generate
  say "Xray running. Subscription: http://$server/clash/config.yaml"
}
require_root
while true; do
  clear; say "===== Xray Reality ====="; say "1. Install or reconfigure"; say "2. Show node"; say "3. Restart"; say "4. Status"; say "5. Remove Xray"; say "0. Back"
  read -r -p "Select: " c
  case "$c" in
    1) install_xray; read -r -p "Press Enter..." _;; 2) load_node_data; say "$VLESS_URI"; say "$SUBSCRIPTION_URL"; read -r -p "Press Enter..." _;;
    3) systemctl restart xray;; 4) systemctl --no-pager status xray || true; read -r -p "Press Enter..." _;;
    5) confirm "Remove Xray and generated node data?" && { bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge; rm -f "$NODE_FILE" "$WEB_ROOT/config.yaml"; };; 0) exit;; *) say "Invalid selection.";;
  esac
done
