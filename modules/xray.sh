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

# 主节点 inbound：VLESS + Reality（TCP）
inbound_json() {
  local port="$1" uuid="$2" private="$3" short="$4"
  printf '{"listen":"0.0.0.0","port":%s,"protocol":"vless","settings":{"clients":[{"id":"%s","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"%s","xver":0,"serverNames":["%s"],"privateKey":"%s","shortIds":["%s"]}}}' \
    "$port" "$uuid" "$REALITY_DEST" "$SNI" "$private" "$short"
}

# WiFi 跳验证 inbound：Vmess + mKCP（UDP）+ DNS 伪装（对齐 3x-ui / 博客方案）。
# 关键：走 UDP —— 热点为跳转 Web 认证页会放行 UDP 53 的 DNS 报文，Reality(TCP) 过不去、mKCP 能过。
# 参数与 3x-ui 默认一致：MTU 1350 / TTI 50 / 上下行 20MB/s / buffer 2。
#
# ⚠⚠ Xray v26.1.31+ 移除了 kcpSettings 的 header/seed，DNS 伪装迁入 streamSettings.finalmask 的
#    UDP 掩码，且有两层语义与世代差异（以下均经真实核心互联实测/源码考据）：
#
#   1) 旧版 header:{type:dns} 的线上格式是「DNS 头 + fnv/XOR 混淆」双层叠加：
#      旧版 GetSecurity() 在未配置 seed 时默认返回 SimpleAuthenticator（fnv+XOR），
#      header 只是额外叠加的伪装头。所以正确复刻必须两层都配。
#
#   2) 两代核心的掩码类型名不同（26.9.9 已删除 header-dns/mkcp-original，只认 mkcp-legacy）：
#      - v26.2.x ~ v26.3.x: {"type":"header-dns","settings":{"domain":域名}} + {"type":"mkcp-original"}
#      - v26.7.x+ / main:   {"type":"mkcp-legacy","settings":{"header":"dns","value":域名}}
#                           + {"type":"mkcp-legacy"}（空 = 旧默认 XOR）
#
#   3) inbound 与 outbound 的数组封装方向相反：v2rayN(26.9.9) 客户端生成的 outbound 数组是
#      [ {空=XOR}, {dns} ]，则 inbound 服务端必须用逆序 [ {dns}, {空=XOR} ]（已用
#      26.3.27 服务端 + 26.9.9 客户端真实互联实测：逆序 HTTP 200 互通，同序 invalid auth）。
#      ⚠ 26.7+/26.9.x 服务端的 mkcp-legacy 组合尚未找到与 v2rayN 客户端互通的实测组合
#        （多种排列均 invalid auth / 超时，核心行为在 26.9 有变化），如升级核心后失效请反馈。
#
#   文档：https://xtls.github.io/config/transports/mkcp.html 与 /finalmask.html
wifi_inbound_json() {
  local port="$1" uuid="$2" domain="$3" style="${4:-mkcp-legacy}" masks
  if [[ "$style" == "mkcp-legacy" ]]; then
    # 26.7+：mkcp-legacy(header=dns,value=域名) ≙ header-dns；mkcp-legacy(空) ≙ mkcp-original
    masks='[{"type":"mkcp-legacy","settings":{"header":"dns","value":"'"$domain"'"}},{"type":"mkcp-legacy"}]'
  else
    # 26.2~26.3：header-dns + mkcp-original 双层，顺序为 v2rayN 客户端数组的逆序（实测互通）
    masks='[{"type":"header-dns","settings":{"domain":"'"$domain"'"}},{"type":"mkcp-original"}]'
  fi
  printf '{"listen":"0.0.0.0","port":%s,"protocol":"vmess","settings":{"clients":[{"id":"%s","alterId":0}]},"streamSettings":{"network":"kcp","security":"none","kcpSettings":{"mtu":1350,"tti":50,"uplinkCapacity":20,"downlinkCapacity":20,"congestion":false,"readBufferSize":2,"writeBufferSize":2},"finalmask":{"udp":%s}}}' \
    "$port" "$uuid" "$masks"
}

# 写入配置并用 xray run -test 校验。WiFi DNS 伪装的掩码类型名随核心版本不同
# （mkcp-legacy / header-dns，见 wifi_inbound_json 注释），此处自动适配：
# 先按 mkcp-legacy 生成，校验报 unknown config id 时换 header-dns 重建再验，反之亦然。
write_xray_config() {
  local style test_err
  for style in mkcp-legacy header-dns; do
    if _write_xray_config_once "$style"; then
      return 0
    fi
    # 只有「掩码类型名不识别」才值得换一种格式重试；其他错误重试无意义
    test_err="$(xray run -test -c "$XRAY_CONFIG" 2>&1 || true)"
    if [[ "$test_err" != *"unknown config id"* ]]; then
      say "✗ Xray 配置校验失败（与 DNS 伪装格式无关），详情："
      printf '%s\n' "$test_err" | tail -n 5
      return 1
    fi
    say "提示: 当前 Xray 核心不识别 $style 伪装格式，切换为另一种格式重试..."
  done
  say "✗ mkcp-legacy 与 header-dns 两种伪装格式均被当前核心拒绝，请检查 Xray 版本。"
  return 1
}

_write_xray_config_once() {
  local style="$1" ins=() joined
  if [[ -n "${UUID:-}" && -n "${PRIVATE_KEY:-}" && -n "${PORT:-}" && -n "${SHORT_ID:-}" ]]; then
    ins+=("$(inbound_json "$PORT" "$UUID" "$PRIVATE_KEY" "$SHORT_ID")")
  fi
  if [[ -n "${WIFI_UUID:-}" && -n "${WIFI_PORT:-}" ]]; then
    ins+=("$(wifi_inbound_json "$WIFI_PORT" "$WIFI_UUID" "${WIFI_DOMAIN:-$SNI}" "$style")")
  fi
  ((${#ins[@]})) || { say "没有可写入的节点：主节点与 WiFi 节点信息均缺失。"; return 1; }
  joined="$(IFS=,; echo "${ins[*]}")"
  install -d -m 0755 "$(dirname "$XRAY_CONFIG")"
  printf '{"log":{"loglevel":"warning"},"inbounds":[%s],"outbounds":[{"protocol":"freedom"}]}\n' "$joined" >"$XRAY_CONFIG"
  # 配置校验失败必须显式报错返回（条件上下文里 set -e 不会兜底，静默继续会用坏配置重启）
  xray run -test -c "$XRAY_CONFIG" >/dev/null 2>&1 || return 1
}

# 写入新配置后必须 (re)start，不能只靠 enable --now：服务已在运行时它是 no-op，
# 进程会继续加载旧配置，表现为“配置写了新端口却没监听新端口”。
restart_xray_and_wait() {
  local port="$1" proto="${2:-tcp}" ok=0
  systemctl enable xray
  systemctl daemon-reload 2>/dev/null || true
  if service_is_active xray; then systemctl restart xray; else systemctl start xray; fi
  # 校验端口是否真的监听：Xray 报 running 但未绑定端口是常见“参数对却连不上”陷阱
  if [[ "$proto" == "udp" ]]; then
    if wait_for_listen_udp "$port" 20; then ok=1; fi
  else
    if wait_for_listen "$port" 20; then ok=1; fi
  fi
  if (( ! ok )); then
    say "⚠ 警告: Xray 未在 $proto/$port 端口监听，正在排查..."
    ss -lntup 2>/dev/null | grep -w "$port" || say "（当前无任何进程监听该端口）"
    say "（Xray 实际监听端口：）"; ss -lntup 2>/dev/null | grep -i xray || say "（ss 未列出 xray，可能未真正启动）"
    say "--- 最近日志 ---"; journalctl -u xray -n 20 --no-pager 2>/dev/null || true
    say "--- 实际启动命令 ---"; systemctl show xray -p ExecStart 2>/dev/null || true
    say "✗ Xray 未监听 $proto/$port（常见原因：端口被占用 / systemd 单元 ExecStart 被覆写 / 配置未加载）。"
    return 1
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
  if port_in_use 53 || port_in_use_udp 53; then restore_dns_53; return 1; fi
  if command -v getent >/dev/null 2>&1 && ! getent hosts "$SNI" >/dev/null 2>&1; then
    say "⚠ 释放 53 后 DNS 解析失败（Reality 需要解析 $SNI），已自动回滚。"
    restore_dns_53
    return 1
  fi
  return 0
}

install_xray() {
  # 主节点（常规端口 443/8443/2053/2083）。重建配置时保留已存在的 WiFi 专属节点 inbound。
  # 同 install_wifi_node：被菜单以条件上下文调用时 set -e 不生效，失败必须显式 return 1。
  local port keys private public uuid short server
  say "正在准备 Xray Reality 主节点..."
  ensure_xray || { say "✗ Xray 安装/检查失败（多为无法访问 GitHub 下载安装脚本）。请检查服务器出网后重试。"; return 1; }
  command -v xray >/dev/null 2>&1 || { say "✗ 未找到 xray 命令，无法继续。"; return 1; }
  port="$(choose_available_port)" || { say "✗ 端口 443/8443/2053/2083 均被占用，请释放后重试。"; return 1; }
  uuid="$(xray uuid)" || { say "✗ 生成 UUID 失败（xray 命令异常）。"; return 1; }
  keys="$(xray x25519)" || { say "✗ 生成 Reality 密钥失败（xray 命令异常）。"; return 1; }
  private="$(key 'private' "$keys")"; public="$(key 'public' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || { say "✗ 无法读取 Xray Reality 密钥（x25519 输出异常）。"; return 1; }
  short="$(openssl rand -hex 8)"
  server="$(detect_public_ip)" || { say "✗ 无法获取公网 IPv4（api.ipify.org / ifconfig.me / ipv4.icanhazip.com 均不可达）。请检查服务器出网后重试。"; return 1; }
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
  write_xray_config || { say "✗ Xray 配置写入/校验失败，主节点未生效（详见上方输出）。"; return 1; }
  restart_xray_and_wait "$port" || return 1
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow "$port/tcp" || true
  "$SCRIPT_DIR/subscription.sh" generate || say "⚠ 订阅生成失败（不影响节点本体），可稍后在主菜单 2 重新生成。"
  say "Xray 已启动并在 $port 监听。订阅地址见上方输出（含随机令牌，也可在主菜单 7 查看）。"
}

install_wifi_node() {
  # WiFi web 跳验证：独立的专属节点 —— Vmess + mKCP（UDP）+ DNS 伪装，不覆盖主节点。
  # 热点为把用户跳到 Web 认证页会放行 UDP 53 的 DNS 报文，故走 UDP:53（Reality 是 TCP，过不去）。
  # 注意：本函数可能被菜单以 `if ! install_wifi_node` 调用（条件上下文会挂起 set -e），
  # 故每个可能失败的步骤都必须显式 `|| { say ...; return 1; }`，绝不能依赖 set -e 兜底。
  local port="" uuid server domain stale
  say "正在准备 WiFi 跳验证节点（Vmess + mKCP，UDP 53）..."
  ensure_xray || { say "✗ Xray 安装/检查失败（多为无法访问 GitHub 下载安装脚本）。请检查服务器出网后重试。"; return 1; }
  command -v xray >/dev/null 2>&1 || { say "✗ 未找到 xray 命令，无法继续。请先运行 Xray 菜单 1 安装主节点。"; return 1; }
  server="$(detect_public_ip)" || { say "✗ 无法获取公网 IPv4（api.ipify.org / ifconfig.me / ipv4.icanhazip.com 均不可达）。请检查服务器出网后重试。"; return 1; }
  if [[ -f "$NODE_FILE" ]]; then source "$NODE_FILE" 2>/dev/null || true; fi
  domain="${WIFI_DOMAIN:-$SNI}"
  # 已存在 WiFi 节点且端口仍在 UDP 监听 → 复用，避免重跑时把 Xray 自己占的 53 误判为“被占用”而漂移
  if [[ "${WIFI:-0}" == "1" && -n "${WIFI_PORT:-}" ]] \
     && ss -lnup 2>/dev/null | grep -w "${WIFI_PORT}" | grep -qi xray; then
    port="$WIFI_PORT"
    say "检测到已存在的 WiFi 节点（UDP $port）：复用该端口并轮换 UUID。"
  fi
  if [[ -z "$port" ]]; then
    if ! port_in_use 53 && ! port_in_use_udp 53; then
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
  uuid="$(xray uuid)" || { say "✗ 生成 Vmess UUID 失败（xray 命令异常）。"; return 1; }
  [[ -n "$uuid" ]] || { say "✗ 生成的 Vmess UUID 为空。"; return 1; }
  install -d -m 0755 "$DATA_DIR"
  [[ -f "$NODE_FILE" ]] || install -m 0600 /dev/null "$NODE_FILE"
  # Vmess 分享链接：vmess://<base64(JSON)>，v2rayN/v2rayNG 可直接导入（net=kcp + type=dns 伪装）
  local vj vuri
  vj="$(printf '{"v":"2","ps":"WiFi-%s","add":"%s","port":"%s","id":"%s","aid":"0","scy":"auto","net":"kcp","type":"dns","host":"%s","path":"","tls":"","sni":"","alpn":"","fp":""}' "$server" "$server" "$port" "$uuid" "$domain")"
  vuri="vmess://$(printf '%s' "$vj" | base64 -w0)"
  env_upsert "$NODE_FILE" SERVER "$server"
  env_upsert "$NODE_FILE" SNI "$SNI"
  env_upsert "$NODE_FILE" WIFI 1
  env_upsert "$NODE_FILE" WIFI_PORT "$port"
  env_upsert "$NODE_FILE" WIFI_UUID "$uuid"
  env_upsert "$NODE_FILE" WIFI_DOMAIN "$domain"
  env_upsert "$NODE_FILE" WIFI_NODE_NAME "WiFi-$server"
  env_upsert "$NODE_FILE" WIFI_URI "\"$vuri\""
  # 清掉旧版（Reality 版 WiFi 节点）残留键，避免和 mKCP 节点混淆
  for stale in WIFI_PRIVATE_KEY WIFI_PUBLIC_KEY WIFI_SHORT_ID; do sed -i "/^${stale}=/d" "$NODE_FILE"; done
  chmod 0600 "$NODE_FILE"
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  write_xray_config || { say "✗ Xray 配置写入/校验失败，WiFi 节点未生效（详见上方输出）。"; return 1; }
  restart_xray_and_wait "$port" udp || return 1
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && { ufw allow "$port/udp"; ufw allow "$port/tcp"; } || true
  "$SCRIPT_DIR/subscription.sh" generate || say "⚠ 订阅生成失败（不影响节点本体），可稍后在主菜单 2 重新生成。"
  say "✓ WiFi web 跳验证专属节点已就绪：Vmess + mKCP，监听 UDP $port（伪装 DNS）。"
  say "  独立于主节点（各自 inbound、各自端口），主节点仍监听 ${PORT:-（未配置）}，不受影响。"
  say "  专用节点分享链接（vmess://，用 v2rayN / v2rayNG 导入）："
  say "  $WIFI_URI"
  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$domain" >/dev/null 2>&1; then
      say "  ✓ DNS 自检：$domain 可解析。"
    else
      say "  ⚠ DNS 自检失败：服务器解析不了 $domain —— 请检查 /etc/resolv.conf 里的 nameserver 是否可达。"
    fi
  fi
  say "  客户端：必须用 v2rayN / v2rayNG（Xray 核心）导入本链接，开启“DNS 代理 / 防泄漏”并走全局；clash / sing-box 对 UDP:53 伪装支持不佳。"
  say "  注意：阿里云等部分厂商已封禁 53 端口个人使用；深度检测（SNI 阻断 / 真实 DNS 代理）环境仍可能失效。"
}

remove_wifi_node() {
  if [[ ! -f "$NODE_FILE" ]]; then
    say "未找到节点信息（$NODE_FILE），请先在 Xray 菜单 1 安装。"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$NODE_FILE" 2>/dev/null || true
  if [[ "${WIFI:-0}" != "1" ]]; then
    say "当前没有 WiFi 跳验证节点（未记录 WIFI=1），无需移除。"
    say "提示：若你之前用旧版本开通过 WiFi 节点，请先运行本菜单 6 重新生成一次，再回来移除。"
    return 1
  fi
  confirm "确认移除 WiFi 跳验证专属节点（端口 ${WIFI_PORT:-未知}）？" || { say "已取消。"; return 0; }
  local k
  for k in WIFI WIFI_PORT WIFI_UUID WIFI_DOMAIN WIFI_NODE_NAME WIFI_URI; do
    sed -i "/^${k}=/d" "$NODE_FILE"
  done
  # shellcheck disable=SC1090
  source "$NODE_FILE"
  if [[ -n "${UUID:-}" && -n "${PRIVATE_KEY:-}" && -n "${PORT:-}" && -n "${SHORT_ID:-}" ]]; then
    write_xray_config || { say "✗ 重建主节点配置失败，请运行 xray run -test -c $XRAY_CONFIG 查看详情。"; return 1; }
    if service_is_active xray; then systemctl restart xray; else systemctl start xray; fi
    say "WiFi 跳验证节点已移除，主节点保持不变。"
    "$SCRIPT_DIR/subscription.sh" generate || say "⚠ 订阅生成失败，可稍后在主菜单 2 重新生成。"
  else
    systemctl stop xray 2>/dev/null || true
    rm -f "$XRAY_CONFIG"
    say "WiFi 跳验证节点已移除；当前没有主节点，Xray 已停止。"
  fi
}

require_root
while true; do
  clear; say "===== Xray Reality 节点 ====="; say "1. 安装或重新配置"; say "2. 查看节点"; say "3. 重启"; say "4. 状态"; say "5. 移除 Xray"; say "6. WiFi web 跳验证（独立节点 · Vmess+mKCP UDP53）"; say "7. 移除 WiFi 跳验证节点"; say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) if ! install_xray; then say "（主节点未配置完成，原因见上方输出）"; fi; read -r -p "请按回车继续..." _;;
    2) if load_node_data; then say "${VLESS_URI:-（未配置主节点）}"; if [[ "${WIFI:-0}" == "1" ]]; then say "WiFi 跳验证节点: ${WIFI_URI:-}"; fi; say "${SUBSCRIPTION_URL:-订阅尚未生成，请先运行选项 1 或订阅菜单生成。}"; fi; read -r -p "请按回车继续..." _;;
    3) systemctl restart xray;; 4) systemctl --no-pager status xray || true; read -r -p "请按回车继续..." _;;
    5) confirm "Remove Xray and generated node data?" && { bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge; rm -f "$NODE_FILE" "$WEB_ROOT/config.yaml"; };;
    6) if ! install_wifi_node; then say "（WiFi 跳验证节点未配置完成，原因见上方输出）"; fi; read -r -p "请按回车继续..." _;;
    7) if ! remove_wifi_node; then say "（移除未完成，原因见上方输出）"; fi; read -r -p "请按回车继续..." _;; 0) exit;; *) say "无效选择。";;
  esac
done
