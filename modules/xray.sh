#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
SNI="${REALITY_SERVER_NAME:-www.cloudflare.com}"
REALITY_DEST="${REALITY_DEST:-$SNI:443}"
key() { awk -F': *' -v n="$1" 'tolower($0) ~ n {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' <<<"$2"; }
install_xray() {
  local port keys private public uuid short server
  port="$(choose_available_port)" || die "Ports 443, 8443, 2053 and 2083 are in use."
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  uuid="$(xray uuid)"; keys="$(xray x25519)"; private="$(key 'private' "$keys")"; public="$(key 'public' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || die "Unable to read Xray Reality keys."
  short="$(openssl rand -hex 8)"; server="$(detect_public_ip)" || die "Unable to detect public IPv4."
  install -d -m 0755 "$(dirname "$XRAY_CONFIG")" "$DATA_DIR"
  cat >"$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"0.0.0.0","port":$port,"protocol":"vless","settings":{"clients":[{"id":"$uuid","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"$REALITY_DEST","xver":0,"serverNames":["$SNI"],"privateKey":"$private","shortIds":["$short"]}}}],"outbounds":[{"protocol":"freedom"}]}
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
VLESS_URI="vless://$uuid@$server:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$public&sid=$short&type=tcp#Reality-$server"
EOF
  chmod 0600 "$NODE_FILE"
  systemctl enable --now xray
  # 校验端口是否真的监听：Xray 报 running 但未绑定端口是常见"参数对却连不上"陷阱
  if ! wait_for_listen "$port"; then
    say "⚠ 警告: Xray 未在 $port 端口监听，正在排查..."
    ss -lntp 2>/dev/null | grep -w "$port" || say "（当前无任何进程监听 $port）"
    say "--- 最近日志 ---"; journalctl -u xray -n 20 --no-pager 2>/dev/null || true
    say "--- 实际启动命令 ---"; systemctl show xray -p ExecStart 2>/dev/null || true
    die "Xray 未监听 $port。请检查上方日志（常见原因：端口被占用 / systemd 单元 ExecStart 被覆写 / 配置未加载）。"
  fi
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow "$port/tcp" || true
  "$SCRIPT_DIR/subscription.sh" generate
  say "Xray 已启动并在 $port 监听。订阅地址见上方输出（含随机令牌，也可在主菜单 9 查看）。"
}
require_root
while true; do
  clear; say "===== Xray Reality 节点 ====="; say "1. 安装或重新配置"; say "2. 查看节点"; say "3. 重启"; say "4. 状态"; say "5. 移除 Xray"; say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) install_xray; read -r -p "请按回车继续..." _;; 2) load_node_data; say "$VLESS_URI"; say "${SUBSCRIPTION_URL:-订阅尚未生成，请先运行选项 1 或订阅菜单生成。}"; read -r -p "请按回车继续..." _;;
    3) systemctl restart xray;; 4) systemctl --no-pager status xray || true; read -r -p "请按回车继续..." _;;
    5) confirm "Remove Xray and generated node data?" && { bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge; rm -f "$NODE_FILE" "$WEB_ROOT/config.yaml"; };; 0) exit;; *) say "无效选择。";;
  esac
done
