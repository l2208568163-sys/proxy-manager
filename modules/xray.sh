#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ===== 链路设计（v3.4.0）=====
# 主力：VLESS + Vision + REALITY，TCP 443；伪装目标指向本机自建 HTTPS 站点（自签证书）。
# 备用：Hysteria2，UDP 443（与 TCP 443 不冲突）+ 端口跳跃 20000-40000（iptables REDIRECT）。
# Web 面板默认不启用（见 install.sh）。
CAMO_DOMAIN="${REALITY_SERVER_NAME:-}"
if [[ -z "$CAMO_DOMAIN" && -n "${NODE_FILE:-}" && -f "$NODE_FILE" ]]; then
  # 已绑定域名（主菜单 4）时沿用 node.env 里的 SNI，重跑安装不会被自签域名覆盖
  CAMO_DOMAIN="$(grep '^SNI=' "$NODE_FILE" 2>/dev/null | cut -d= -f2- || true)"
fi
CAMO_DOMAIN="${CAMO_DOMAIN:-www.local-cloud.net}"
CAMO_HTTPS_PORT="${CAMO_HTTPS_PORT:-8443}"
CAMO_WEB_DIR="/var/www/camouflage"
CAMO_CERT="/etc/ssl/certs/camo.crt"
CAMO_KEY="/etc/ssl/private/camo.key"
HY2_PORT="${HY2_PORT:-443}"
HY2_HOP="${HY2_HOP:-20000-40000}"
HY2_DIR="/etc/hysteria"

key() { awk -F': *' -v n="$1" 'tolower($0) ~ n {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' <<<"$2"; }

# 本机伪装站：自签证书 + nginx TLS 站点（仅 127.0.0.1:8443），REALITY 的 dest 指向它。
# 未通过 REALITY 认证的扫描流量会看到一张正常的自建网站页面，而不是被拒绝。
install_camouflage_site() {
  require_command openssl
  command -v nginx >/dev/null 2>&1 \
    || die "未安装 nginx：伪装站点依赖 nginx。请先运行 install.sh，或执行 apt-get install -y nginx。"
  install -d -m 0755 "$CAMO_WEB_DIR/assets" /etc/ssl/private
  if [[ ! -f "$CAMO_CERT" || ! -f "$CAMO_KEY" ]]; then
    say "生成自签证书（CN=$CAMO_DOMAIN）..."
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CAMO_KEY" -out "$CAMO_CERT" \
      -subj "/C=US/ST=California/L=San Jose/O=Local Cloud Networks/CN=${CAMO_DOMAIN}" \
      -addext "subjectAltName=DNS:${CAMO_DOMAIN}" >/dev/null 2>&1 \
      || die "自签证书生成失败。"
    chmod 600 "$CAMO_KEY"
  fi
  # 只在站点文件缺失时写入，避免覆盖用户自己替换的页面
  if [[ ! -f "$CAMO_WEB_DIR/index.html" ]]; then
    cat >"$CAMO_WEB_DIR/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Local Cloud Networks — Edge Infrastructure</title>
<link rel="stylesheet" href="/assets/site.css"></head>
<body>
<header><div class="wrap"><div class="brand">Local<span>Cloud</span></div>
<nav><a href="/">Home</a><a href="/#services">Services</a><a href="/#network">Network</a><a href="/#contact">Contact</a></nav></div></header>
<main>
<section class="hero"><div class="wrap">
<h1>Reliable edge infrastructure for modern teams</h1>
<p>We operate small-footprint compute and network nodes across North America and Asia, focused on latency-sensitive workloads and private connectivity.</p>
<div class="cta"><a class="btn" href="#services">Our services</a><a class="btn ghost" href="#contact">Talk to us</a></div>
</div></section>
<section id="services" class="wrap section"><h2>Services</h2><div class="grid">
<div class="card"><h3>Edge Compute</h3><p>Lightweight virtual instances with predictable performance, deployed close to your users.</p></div>
<div class="card"><h3>Private Network</h3><p>Encrypted point-to-point links between your offices, clouds and edge nodes.</p></div>
<div class="card"><h3>Managed DNS</h3><p>Anycast resolution with health checks and low-latency routing policies.</p></div>
</div></section>
<section id="network" class="wrap section muted"><h2>Network status</h2>
<p>All regions operational. Average edge latency under 40 ms within region.</p>
<ul class="stats"><li><b>12</b><span>PoPs</span></li><li><b>99.98%</b><span>Uptime</span></li><li><b>24/7</b><span>NOC</span></li></ul></section>
<section id="contact" class="wrap section"><h2>Contact</h2>
<p>For service enquiries write to <a href="mailto:hello@local-cloud.net">hello@local-cloud.net</a>.</p></section>
</main>
<footer><div class="wrap">© 2026 Local Cloud Networks · San Jose, CA</div></footer>
</body></html>
HTML
    cat >"$CAMO_WEB_DIR/assets/site.css" <<'CSS'
*{box-sizing:border-box;margin:0;padding:0}
body{font:16px/1.65 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2933;background:#fff}
.wrap{max-width:960px;margin:0 auto;padding:0 24px}
header{border-bottom:1px solid #e5e9f0;background:#fff;position:sticky;top:0}
header .wrap{display:flex;align-items:center;justify-content:space-between;height:64px}
.brand{font-weight:700;font-size:19px}.brand span{color:#2f6feb}
nav a{margin-left:22px;color:#52606d;text-decoration:none;font-size:15px}
.hero{background:linear-gradient(180deg,#f7f9fc,#fff);padding:88px 0 72px;border-bottom:1px solid #eef2f7}
.hero h1{font-size:40px;line-height:1.25;max-width:720px;letter-spacing:-.5px}
.hero p{margin-top:18px;max-width:620px;color:#52606d;font-size:17px}
.cta{margin-top:28px;display:flex;gap:12px}
.btn{display:inline-block;padding:11px 20px;border-radius:6px;background:#2f6feb;color:#fff;text-decoration:none;font-size:15px}
.btn.ghost{background:#fff;color:#2f6feb;border:1px solid #cbd5e1}
.section{padding:56px 0}.section h2{font-size:26px;margin-bottom:22px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}
.card{border:1px solid #e5e9f0;border-radius:10px;padding:22px}
.card h3{font-size:17px;margin-bottom:8px}.card p{color:#616e7c;font-size:15px}
.muted{background:#f8fafc;border-top:1px solid #eef2f7;border-bottom:1px solid #eef2f7}
.stats{display:flex;gap:42px;list-style:none;margin-top:20px}
.stats b{display:block;font-size:26px;color:#2f6feb}
.stats span{font-size:13px;color:#7b8794;text-transform:uppercase;letter-spacing:.6px}
footer{padding:26px 0;color:#7b8794;font-size:14px;border-top:1px solid #eef2f7}
CSS
  fi
  cat >/etc/nginx/sites-available/camouflage.conf <<EOF
# Generated by Proxy Manager — REALITY 伪装目标（仅本机 127.0.0.1:${CAMO_HTTPS_PORT}）
server {
    listen 127.0.0.1:${CAMO_HTTPS_PORT} ssl;
    http2 on;
    server_name ${CAMO_DOMAIN};
    ssl_certificate     ${CAMO_CERT};
    ssl_certificate_key ${CAMO_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:4m;
    ssl_session_timeout 1h;
    root  ${CAMO_WEB_DIR};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
  ln -sfn /etc/nginx/sites-available/camouflage.conf /etc/nginx/sites-enabled/camouflage.conf
  nginx -t >/dev/null 2>&1 || die "nginx 配置校验失败：camouflage.conf"
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  say "✓ 伪装站点就绪：https://${CAMO_DOMAIN}（127.0.0.1:${CAMO_HTTPS_PORT}，自签证书）"
}

install_xray() {
  local port=443 keys private public uuid short server dest
  if port_in_use 443 && ! ss -lntp 2>/dev/null | grep -w 443 | grep -qi xray; then
    say "✗ TCP 443 已被占用，主力链路无法监听："
    ss -lntp 2>/dev/null | grep -w 443 || true
    die "请先释放 443 端口（或改用其它端口后重跑）。"
  fi
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  say "配置本机伪装站点（REALITY dest）..."
  install_camouflage_site
  dest="127.0.0.1:${CAMO_HTTPS_PORT}"

  uuid="$(xray uuid)"; keys="$(xray x25519)"
  private="$(key 'private' "$keys")"; public="$(key 'public' "$keys")"
  [[ -n "$uuid" && -n "$private" && -n "$public" ]] || die "Unable to read Xray Reality keys."
  short="$(openssl rand -hex 8)"; server="$(detect_public_ip)" || die "Unable to detect public IPv4."

  install -d -m 0755 "$(dirname "$XRAY_CONFIG")" "$DATA_DIR"
  cat >"$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"0.0.0.0","port":${port},"protocol":"vless","settings":{"clients":[{"id":"${uuid}","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"${dest}","xver":0,"serverNames":["${CAMO_DOMAIN}"],"privateKey":"${private}","shortIds":["${short}"]}}}],"outbounds":[{"protocol":"freedom"}]}
EOF
  xray run -test -c "$XRAY_CONFIG" >/dev/null || die "Xray 配置校验失败。"

  umask 077
  cat >"$NODE_FILE" <<EOF
SERVER=${server}
PORT=${port}
UUID=${uuid}
PRIVATE_KEY=${private}
PUBLIC_KEY=${public}
SHORT_ID=${short}
SNI=${CAMO_DOMAIN}
REALITY_DEST=${dest}
NODE_NAME=Reality-${server}
VLESS_URI="vless://${uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${CAMO_DOMAIN}&fp=chrome&pbk=${public}&sid=${short}&type=tcp#Reality-${server}"
EOF
  chmod 0600 "$NODE_FILE"
  # 必须用 restart：xray 已在运行时 `enable --now` 是 no-op，旧进程会继续跑旧配置
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray
  if ! wait_for_listen 443 20; then
    say "⚠ 警告: Xray 未在 443 监听，正在排查..."
    ss -lntp 2>/dev/null | grep -w 443 || say "（当前无进程监听 443）"
    journalctl -u xray -n 20 --no-pager 2>/dev/null || true
    die "Xray 未监听 443。"
  fi
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && { ufw allow 443/tcp; ufw allow 443/udp; } || true
  "$SCRIPT_DIR/subscription.sh" generate
  say "✓ 主力链路就绪：VLESS+Vision+REALITY 监听 TCP 443，伪装站点 ${CAMO_DOMAIN}"
}

install_hysteria2() {
  local pass ver srv
  require_command curl
  if ! command -v hysteria >/dev/null 2>&1; then
    ver="$(curl -fsSL --max-time 20 https://api.github.com/repos/apernet/hysteria/releases/latest \
      | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 || true)"
    [[ -n "$ver" ]] || die "无法获取 hysteria 最新版本（GitHub API 不可达）。"
    say "下载 hysteria ${ver} ..."
    curl -fsSL --max-time 180 -o /usr/local/bin/hysteria \
      "https://github.com/apernet/hysteria/releases/download/${ver}/hysteria-linux-amd64" \
      || die "hysteria 下载失败。"
    chmod +x /usr/local/bin/hysteria
  fi
  # Hysteria2 强制 TLS：复用伪装站的自签证书
  [[ -f "$CAMO_CERT" && -f "$CAMO_KEY" ]] || install_camouflage_site
  install -d -m 0700 "$HY2_DIR"
  pass="$(openssl rand -hex 16)"
  cat >"$HY2_DIR/config.yaml" <<EOF
listen: :${HY2_PORT}

tls:
  cert: ${CAMO_CERT}
  key: ${CAMO_KEY}

auth:
  type: password
  password: ${pass}

masquerade:
  type: proxy
  proxy:
    url: https://127.0.0.1:${CAMO_HTTPS_PORT}
    rewriteHost: false
    insecure: true

bandwidth:
  up: 100 mbps
  down: 500 mbps
EOF
  chmod 600 "$HY2_DIR/config.yaml"
  cat >/etc/systemd/system/hysteria-server.service <<'EOF'
[Unit]
Description=Hysteria2 Server (UDP)
After=network.target nss-lookup.target
[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable hysteria-server >/dev/null 2>&1 || true
  systemctl restart hysteria-server
  sleep 2
  systemctl is-active hysteria-server >/dev/null || die "hysteria-server 启动失败，请运行 journalctl -u hysteria-server 查看。"

  # 端口跳跃：iptables 把 UDP 范围端口重定向到主监听端口（iptables 范围写法是 20000:40000）
  cat >/etc/systemd/system/hysteria-porthop.service <<EOF
[Unit]
Description=Hysteria2 UDP port hopping (${HY2_HOP} -> ${HY2_PORT})
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'iptables -t nat -C PREROUTING -p udp --dport ${HY2_HOP//-/:} -j REDIRECT --to-ports ${HY2_PORT} 2>/dev/null || iptables -t nat -A PREROUTING -p udp --dport ${HY2_HOP//-/:} -j REDIRECT --to-ports ${HY2_PORT}'
ExecStop=/bin/bash -c 'iptables -t nat -D PREROUTING -p udp --dport ${HY2_HOP//-/:} -j REDIRECT --to-ports ${HY2_PORT} 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable hysteria-porthop >/dev/null 2>&1 || true
  systemctl restart hysteria-porthop
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && { ufw allow "${HY2_PORT}/udp"; ufw allow "${HY2_HOP//-/:}/udp"; ufw reload; } || true

  srv="$(detect_public_ip || true)"
  # 边界：允许先装 Hysteria2 再装主力链路，此时 node.env 还不存在
  install -d -m 0755 "$DATA_DIR"
  [[ -f "$NODE_FILE" ]] || install -m 0600 /dev/null "$NODE_FILE"
  for k in HY2 HY2_PORT HY2_PASSWORD HY2_HOP HY2_SNI; do sed -i "/^${k}=/d" "$NODE_FILE"; done
  {
    echo "HY2=1"
    echo "HY2_PORT=${HY2_PORT}"
    echo "HY2_PASSWORD=${pass}"
    echo "HY2_HOP=${HY2_HOP}"
    echo "HY2_SNI=${CAMO_DOMAIN}"
  } >>"$NODE_FILE"
  chmod 0600 "$NODE_FILE"
  "$SCRIPT_DIR/subscription.sh" generate || true
  say "✓ 备用链路就绪：Hysteria2 UDP ${HY2_PORT}，端口跳跃 ${HY2_HOP}"
  say "  密码：${pass}"
  [[ -n "$srv" ]] && say "  客户端：server ${srv}:${HY2_PORT}，hop ${HY2_HOP}，sni ${CAMO_DOMAIN}，skip-cert-verify"
}

remove_hysteria2() {
  confirm "确认移除 Hysteria2 备用链路（UDP ${HY2_PORT} + 端口跳跃）？" || { say "已取消。"; return 0; }
  systemctl disable --now hysteria-porthop 2>/dev/null || true
  systemctl disable --now hysteria-server 2>/dev/null || true
  rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-porthop.service
  systemctl daemon-reload
  sed -i '/^HY2=/d;/^HY2_PORT=/d;/^HY2_PASSWORD=/d;/^HY2_HOP=/d;/^HY2_SNI=/d' "$NODE_FILE" 2>/dev/null || true
  [[ -f "$NODE_FILE" ]] && "$SCRIPT_DIR/subscription.sh" generate >/dev/null 2>&1 || true
  say "Hysteria2 已移除（配置文件保留在 ${HY2_DIR}）。"
}

require_root
while true; do
  clr; say "===== Xray / 链路管理 ====="
  say "1. 安装或重新配置主力链路（VLESS+Vision+REALITY TCP443）"
  say "2. 查看节点信息"
  say "3. 重启 Xray"
  say "4. 服务状态"
  say "5. 移除 Xray"
  say "6. 安装/重配 Hysteria2 备用链路（UDP${HY2_PORT} + 跳跃 ${HY2_HOP}）"
  say "7. 移除 Hysteria2"
  say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) if ! install_xray; then say "（主力链路未配置完成）"; fi; read -r -p "请按回车继续..." _ || true;;
    2) if load_node_data; then say "$VLESS_URI"; [[ "${HY2:-0}" == "1" ]] && say "Hysteria2: UDP ${HY2_PORT} / hop ${HY2_HOP} / pass ${HY2_PASSWORD}"; say "${SUBSCRIPTION_URL:-订阅尚未生成。}"; fi; read -r -p "请按回车继续..." _ || true;;
    3) systemctl restart xray;;
    4) systemctl --no-pager status xray || true; read -r -p "请按回车继续..." _ || true;;
    5) if confirm "Remove Xray and generated node data?"; then
         bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
         rm -f "$NODE_FILE" "$WEB_ROOT/config.yaml"
       else
         say "已取消。"
       fi;;
    6) if ! install_hysteria2; then say "（Hysteria2 未配置完成）"; fi; read -r -p "请按回车继续..." _ || true;;
    7) remove_hysteria2; read -r -p "请按回车继续..." _ || true;;
    0) exit;;
    *) say "无效选择。";;
  esac
done
