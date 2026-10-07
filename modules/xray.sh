#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
SNI="${REALITY_SERVER_NAME:-www.cloudflare.com}"
REALITY_DEST="${REALITY_DEST:-$SNI:443}"
key() { awk -F': *' -v n="$1" 'tolower($0) ~ n {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' <<<"$2"; }

ensure_xray() {
  command -v xray >/dev/null 2>&1 || \
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

# 生成一个 VLESS-Reality inbound 的 JSON 片段（主节点与 WiFi 节点结构一致，仅端口/密钥不同）
inbound_json() {
  local port="$1" uuid="$2" private="$3" short="$4"
  printf '{"listen":"0.0.0.0","port":%s,"protocol":"vless","settings":{"clients":[{"id":"%s","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"%s","xver":0,"serverNames":["%s"],"privateKey":"%s","shortIds":["%s"]}}}' \
    "$port" "$uuid" "$REALITY_DEST" "$SNI" "$private" "$short"
}

# 依据 node.env 重建 Xray 配置：主节点与 WiFi 专属节点各自独立 inbound，互不覆盖
write_xray_config() {
  local ins=()
  if [[ -n "${UUID:-}" && -n "${PRIVATE_KEY:-}" && -n "${PORT:-}" && -n "${SHORT_ID:-}" ]]; then
    ins+=("$(inbound_json "$PORT" "$UUID" "$PRIVATE_KEY" "$SHORT_ID")")
  fi
  if [[ -n "${WIFI_UUID:-}" && -n "${WIFI_PRIVATE_KEY:-}" && -n "${WIFI_PORT:-}" && -n "${WIFI_SHORT_ID:-}" ]]; then
    ins+=("$(inbound_json "$WIFI_PORT" "$WIFI_UUID" "$WIFI_PRIVATE_KEY" "$WIFI_SHORT_ID")")
  fi
  ((${#ins[@]})) || die "没有可写入的节点：主节点与 WiFi 节点信息均缺失。"
  local joined; joined="$(IFS=,; echo "${ins[*]}")"
  install -d -m 0755 "$(dirname "$XRAY_CONFIG")"
  printf '{"log":{"loglevel":"warning"},"inbounds":[%s],"outbounds":[{"protocol":"freedom"}]}\n' "$joined" >"$XRAY_CONFIG"
  xray run -test -c "$XRAY_CONFIG" >/dev/null
}

# 写入新配置后必须 (re)start，不能只靠 enable --now：服务已在运行时它是 no-op，
# 进程会继续加载旧配置，表现为“配置写了新端口却没监听新端口”。
restart_xray_and_wait() {
  local port="$1"
  systemctl enable xray
  systemctl daemon-reload 2>/dev/null || true
  if service_is_active xray; then systemctl restart xray; else systemctl start xray; fi
  # 校验端口是否真的监听：Xray 报 running 但未绑定端口是常见“参数对却连不上”陷阱
  if ! wait_for_listen "$port" 20; then
    say "⚠ 警告: Xray 未在 $port 端口监听，正在排查..."
    ss -lntp 2>/dev/null | grep -w "$port" || say "（当前无任何进程监听 $port）"
    say "（Xray 实际监听端口：）"; ss -lntp 2>/dev/null | grep -i xray || say "（ss 未列出 xray，可能未真正启动）"
    say "--- 最近日志 ---"; journalctl -u xray -n 20 --no-pager 2>/dev/null || true
    say "--- 实际启动命令 ---"; systemctl show xray -p ExecStart 2>/dev/null || true
    die "Xray 未监听 $port。请检查上方日志（常见原因：端口被占用 / systemd 单元 ExecStart 被覆写 / 配置未加载）。"
  fi
}

# 回滚：还原 systemd-resolved 的端口 53 占用配置与 /etc/resolv.conf
restore_dns_53() {
  rm -f /etc/systemd/resolved.conf.d/proxy-manager-port53.conf
  if [[ -f /etc/resolv.conf.bak.proxy-manager ]]; then
    rm -f /etc/resolv.conf
    cp /etc/resolv.conf.bak.proxy-manager /etc/resolv.conf
  fi
  systemctl restart systemd-resolved 2>/dev/null || true
}

# 端口 53 常被 systemd-resolved 的 stub 监听（127.0.0.53:53）占用，导致 Xray 无法绑定 0.0.0.0:53。
# 关闭该 stub 以让出 53。两个必须绕开的坑：
#  1) Ubuntu 下 /etc/resolv.conf 多为指向 /run/systemd/resolve/stub-resolv.conf 的符号链接，
#     直接重定向写会写进那个 stub 文件，而 resolved 重启后会重新生成它 ——
#     于是 127.0.0.53 已停监听、stub 文件又被覆盖，DNS 彻底断掉。必须先删链接再落成真实文件。
#  2) DNS 一断，Reality 的 dest（SNI 域名）就解析不了，节点握手必定失败。
#     故保留机器当前在用的 DNS（别硬切 1.1.1.1/8.8.8.8，国内机器常不通），并在改完后实测解析，失败即回滚。
free_port_53() {
  systemctl is-active --quiet systemd-resolved 2>/dev/null || return 1
  local ns ns1 ns2
  ns="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep -v '^127\.0\.0\.53$' | head -2)"
  ns1="$(printf '%s\n' "$ns" | sed -n 1p)"; ns2="$(printf '%s\n' "$ns" | sed -n 2p)"
  [[ -n "$ns1" ]] || ns1="223.5.5.5"
  [[ -n "$ns2" ]] || ns2="119.29.29.29"
  install -d -m 0755 /etc/systemd/resolved.conf.d
  cat >/etc/systemd/resolved.conf.d/proxy-manager-port53.conf <<EOF
[Resolve]
DNS=$ns1 $ns2
DNSStubListener=no
EOF
  if [[ -e /etc/resolv.conf && ! -f /etc/resolv.conf.bak.proxy-manager ]]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak.proxy-manager 2>/dev/null || true
  fi
  rm -f /etc/resolv.conf
  printf 'nameserver %s\nnameserver %s\noptions timeout:2 attempts:2\n' "$ns1" "$ns2" >/etc/resolv.conf
  systemctl restart systemd-resolved 2>/dev/null || true
  sleep 2
  if port_in_use 53; then restore_dns_53; return 1; fi
  if command -v getent >/dev/null 2>&1 && ! getent hosts "$SNI" >/dev/null 2>&1; then
    say "⚠ 释放 53 后 DNS 解析失败（Reality 需要解析 $SNI），已自动回滚。"
    restore_dns_53
    return 1
  fi
  return 0
}

install_xray() {
  # 主节点（常规端口 443/8443/2053/2083）。重建配置时保留已存在的 WiFi 专属节点 inbound。
  local port keys private public uuid short server
  ensure_xray
  port="$(choose_available_port)" || die "Ports 443, 8443, 2053 and 2083 are in use."
  uuid="$(xray uuid)"; keys="$(xray x25519)"; private="$(key 'private' "$keys")"; public="$(key 'public' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || die "Unable to read Xray Reality keys."
  short="$(openssl rand -hex 8)"; server="$(detect_public_ip)" || die "Unable to detect public IPv4."
  install -d -m 0755 "$DATA_DIR"
  [[ -f "$NODE_FILE" ]] || install -m 0600 /dev/null "$NODE_FILE"
  env_upsert "$NODE_FILE" SERVER "$server"
  env_upsert "$NODE_FILE" PORT "$port"
  env_upsert "$NODE_FILE" UUID "$uuid"
  env_upsert "$NODE_FILE" PRIVATE_KEY "$private"
  env_upsert "$NODE_FILE" PUBLIC_KEY "$public"
  env_upsert "$NODE_FILE" SHORT_ID "$short"
  env_upsert "$NODE_FILE" SNI "$SNI"
  env_upsert "$NODE_FILE" NODE_NAME "Reality-$server"
  env_upsert "$NODE_FILE" BYPASS 0
  env_upsert "$NODE_FILE" VLESS_URI "\"vless://$uuid@$server:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$public&sid=$short&type=tcp#Reality-$server\""
  chmod 0600 "$NODE_FILE"
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  write_xray_config
  restart_xray_and_wait "$port"
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow "$port/tcp" || true
  "$SCRIPT_DIR/subscription.sh" generate
  say "Xray 已启动并在 $port 监听。订阅地址见上方输出（含随机令牌，也可在主菜单 7 查看）。"
}

install_wifi_node() {
  # WiFi web 跳验证：独立的专属节点（独立 inbound、独立密钥、独立端口），不覆盖主节点。
  # 端口落在网关默认放行的 DNS/DHCP/NTP（53/67/68/123），把流量伪装成 DNS 以绕过热点 Web 认证。
  local port="" uuid keys private public short server
  ensure_xray
  server="$(detect_public_ip)" || die "Unable to detect public IPv4."
  if [[ -f "$NODE_FILE" ]]; then source "$NODE_FILE" 2>/dev/null || true; fi
  # 已存在 WiFi 节点且该端口正由 Xray 监听 → 直接复用。
  # 否则第二次运行会把"Xray 自己占着 53"误判成"53 被别的程序占用"，从而漂移到 67/68/123。
  if [[ "${WIFI:-0}" == "1" && -n "${WIFI_PORT:-}" ]] \
     && ss -lntp 2>/dev/null | grep -w "${WIFI_PORT}" | grep -qi xray; then
    port="$WIFI_PORT"
    say "检测到已存在的 WiFi 节点（端口 $port）：复用该端口并轮换密钥。"
  fi
  if [[ -z "$port" ]]; then
    if ! port_in_use 53; then
      port=53
    else
      say "端口 53 已被占用（最常见：systemd-resolved 的 127.0.0.53 stub 监听）。53 是网关放行率最高的端口。"
      if confirm "释放 53 给 WiFi 节点？（将关闭 stub 监听；服务器改用静态 DNS 并保留现有 DNS 服务器，原 /etc/resolv.conf 会备份为 .bak.proxy-manager）"; then
        if free_port_53; then port=53; else say "⚠ 释放 53 失败（或释放后 DNS 不可用已回滚），将回退到其他放行端口。"; fi
      fi
    fi
  fi
  if [[ -z "$port" ]]; then
    port="$(choose_bypass_port)" || die "WiFi 跳验证端口 53/67/68/123 均被占用，请释放后重试。"
  fi
  uuid="$(xray uuid)"; keys="$(xray x25519)"; private="$(key 'private' "$keys")"; public="$(key 'public' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || die "Unable to read Xray Reality keys."
  short="$(openssl rand -hex 8)"
  install -d -m 0755 "$DATA_DIR"
  [[ -f "$NODE_FILE" ]] || install -m 0600 /dev/null "$NODE_FILE"
  env_upsert "$NODE_FILE" SERVER "$server"
  env_upsert "$NODE_FILE" SNI "$SNI"
  env_upsert "$NODE_FILE" WIFI 1
  env_upsert "$NODE_FILE" WIFI_PORT "$port"
  env_upsert "$NODE_FILE" WIFI_UUID "$uuid"
  env_upsert "$NODE_FILE" WIFI_PRIVATE_KEY "$private"
  env_upsert "$NODE_FILE" WIFI_PUBLIC_KEY "$public"
  env_upsert "$NODE_FILE" WIFI_SHORT_ID "$short"
  env_upsert "$NODE_FILE" WIFI_NODE_NAME "WiFi-$server"
  env_upsert "$NODE_FILE" WIFI_URI "\"vless://$uuid@$server:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$public&sid=$short&type=tcp#WiFi-$server\""
  chmod 0600 "$NODE_FILE"
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  write_xray_config
  restart_xray_and_wait "$port"
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && { ufw allow "$port/tcp"; ufw allow "$port/udp"; } || true
  "$SCRIPT_DIR/subscription.sh" generate
  say "✓ WiFi web 跳验证专属节点已就绪：监听 $port（网关常放行的 DNS/DHCP/NTP 端口）。"
  say "  该节点独立于主节点（各自 inbound、各自密钥），主节点仍监听 ${PORT:-（未配置）}，不受影响。"
  say "  专用节点链接：$WIFI_URI"
  # Reality 的 dest 依赖 DNS 解析：解析不了就握不上手，表现为“端口在监听但死活连不上”
  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$SNI" >/dev/null 2>&1; then
      say "  ✓ DNS 自检：$SNI 可解析（Reality dest 正常）。"
    else
      say "  ⚠ DNS 自检失败：服务器解析不了 $SNI，Reality 握手必然失败 —— 请检查 /etc/resolv.conf 里的 nameserver 是否可达。"
    fi
  fi
  say "  客户端：请用 v2rayN / v2rayNG（Xray 核心）导入并开启“DNS 代理 / 防泄漏”走全局；clash / sing-box 对 53 端口伪装支持不佳。"
  say "  注意：阿里云等部分厂商已封禁 53 端口个人使用；深度检测（SNI 阻断 / 真实 DNS 代理）环境仍可能失效。"
  say "  限制：Reality 只能跑 TCP，所以本节点是 TCP:$port；部分热点只放行 UDP 53（真正的 DNS 报文），那种环境下仍会失败。"
}

remove_wifi_node() {
  [[ -f "$NODE_FILE" ]] || die "未找到节点信息，请先安装 Xray Reality。"
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  [[ "${WIFI:-0}" == "1" ]] || die "当前没有 WiFi 跳验证节点。"
  confirm "确认移除 WiFi 跳验证专属节点（端口 ${WIFI_PORT:-未知}）？" || { say "已取消。"; return; }
  local k
  for k in WIFI WIFI_PORT WIFI_UUID WIFI_PRIVATE_KEY WIFI_PUBLIC_KEY WIFI_SHORT_ID WIFI_NODE_NAME WIFI_URI; do
    sed -i "/^${k}=/d" "$NODE_FILE"
  done
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  if [[ -n "${UUID:-}" && -n "${PRIVATE_KEY:-}" && -n "${PORT:-}" && -n "${SHORT_ID:-}" ]]; then
    write_xray_config
    if service_is_active xray; then systemctl restart xray; else systemctl start xray; fi
    say "WiFi 跳验证节点已移除，主节点保持不变。"
    "$SCRIPT_DIR/subscription.sh" generate
  else
    systemctl stop xray 2>/dev/null || true
    rm -f "$XRAY_CONFIG"
    say "WiFi 跳验证节点已移除；当前没有主节点，Xray 已停止。"
  fi
}

require_root
while true; do
  clear; say "===== Xray Reality 节点 ====="; say "1. 安装或重新配置"; say "2. 查看节点"; say "3. 重启"; say "4. 状态"; say "5. 移除 Xray"; say "6. WiFi web 跳验证（独立节点 · 端口53）"; say "7. 移除 WiFi 跳验证节点"; say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) install_xray; read -r -p "请按回车继续..." _;;
    2) load_node_data; say "${VLESS_URI:-（未配置主节点）}"; if [[ "${WIFI:-0}" == "1" ]]; then say "WiFi 跳验证节点: ${WIFI_URI:-}"; fi; say "${SUBSCRIPTION_URL:-订阅尚未生成，请先运行选项 1 或订阅菜单生成。}"; read -r -p "请按回车继续..." _;;
    3) systemctl restart xray;; 4) systemctl --no-pager status xray || true; read -r -p "请按回车继续..." _;;
    5) confirm "Remove Xray and generated node data?" && { bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge; rm -f "$NODE_FILE" "$WEB_ROOT/config.yaml"; };;
    6) install_wifi_node; read -r -p "请按回车继续..." _;;
    7) remove_wifi_node; read -r -p "请按回车继续..." _;; 0) exit;; *) say "无效选择。";;
  esac
done
