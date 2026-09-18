#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

WEB_DIR="$BASE_DIR/web"
DATA_DIR="$BASE_DIR/data"
WEB_ENV="$DATA_DIR/web.env"

install_panel() {
  require_command python3
  # 用 venv 隔离依赖，规避系统 Python 的 PEP 668 (externally-managed) 限制
  # 若 venv 已存在则复用，但始终重装/补齐依赖（修复旧 venv 缺包，如 python-multipart）
  [[ -x "$WEB_DIR/venv/bin/pip" ]] || python3 -m venv "$WEB_DIR/venv"
  "$WEB_DIR/venv/bin/pip" install -q --upgrade pip
  "$WEB_DIR/venv/bin/pip" install -q -r "$WEB_DIR/requirements.txt"

  # 生成随机后台密码（仅首次），不写死默认密码，避免随仓库泄露
  install -d -m 0700 "$DATA_DIR"
  if [[ ! -f "$WEB_ENV" ]]; then
    local pass
    pass="$(openssl rand -hex 12)"
    umask 077
    cat >"$WEB_ENV" <<EOF
WEB_USER=admin
WEB_PASS=$pass
EOF
    chmod 0600 "$WEB_ENV"
    say "已生成后台随机密码，请妥善保管（也可编辑 $WEB_ENV 自行修改）："
    say "  用户名: admin"
    say "  密码:   $pass"
  else
    say "检测到已存在 $WEB_ENV，沿用其中的账号密码。"
  fi

  # 生成 systemd 单元；路径随部署位置（/root/proxy-manager 或 /opt/proxy-manager）自适应
  cat >/etc/systemd/system/proxy-web.service <<EOF
[Unit]
Description=Proxy Manager Web Console
After=network.target

[Service]
WorkingDirectory=$WEB_DIR
ExecStart=$WEB_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now proxy-web
  command -v ufw >/dev/null && ufw status | grep -q 'Status: active' && ufw allow 8080/tcp || true
  say "Web 管理面板已启动：http://$(detect_public_ip || echo '<服务器IP>'):8080"
  say "提示：面板已带登录认证，但公网暴露仍建议加反向代理或仅本地/SSH 隧道访问。"
}

start_panel() { systemctl start proxy-web; say "Web 面板已启动：http://$(detect_public_ip || echo '<服务器IP>'):8080"; }
stop_panel()  { systemctl stop proxy-web; say "Web 面板已停止。"; }
show_address() { say "Web 控制台: http://$(detect_public_ip || echo '<服务器IP>'):8080"; }

show_credentials() {
  if [[ -f "$WEB_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$WEB_ENV"
    say "用户名: ${WEB_USER:-admin}"
    say "密码:   ${WEB_PASS:-<未设置，请运行重置密码>}"
  else
    say "尚未生成 $WEB_ENV，请先安装面板（选项 1）。"
  fi
}

reset_password() {
  require_command openssl
  local pass user="admin"
  [[ -f "$WEB_ENV" ]] && user="$( ( source "$WEB_ENV"; echo "${WEB_USER:-admin}" ) )"
  pass="$(openssl rand -hex 12)"
  install -d -m 0700 "$DATA_DIR"
  umask 077
  cat >"$WEB_ENV" <<EOF
WEB_USER=$user
WEB_PASS=$pass
EOF
  chmod 0600 "$WEB_ENV"
  say "已重置后台密码："
  say "  用户名: $user"
  say "  密码:   $pass"
  if systemctl is-active --quiet proxy-web 2>/dev/null; then systemctl restart proxy-web; say "已重启 Web 面板使新密码生效。"; fi
}

# 非交互模式（供 install.sh / 主菜单调用）
case "${1:-}" in
  install) require_root; install_panel; exit 0;;
  start)   require_root; start_panel; exit 0;;
  stop)    require_root; stop_panel; exit 0;;
  restart) require_root; systemctl restart proxy-web; exit 0;;
  status)  require_root; systemctl --no-pager status proxy-web; exit 0;;
  address) show_address; exit 0;;
  creds)   show_credentials; exit 0;;
  reset)   require_root; reset_password; exit 0;;
  "") ;;
  *) die "Usage: webpanel.sh [install|start|stop|restart|status|address|creds|reset]";;
esac

require_root
while true; do
  clear; say "===== Web 管理中心 ====="
  say "1. 安装并启动面板"; say "2. 启动面板"; say "3. 停止面板"; say "4. 查看访问地址"
  say "5. 查看账号密码"; say "6. 重置密码"; say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) install_panel; read -r -p "请按回车继续..." _;;
    2) start_panel; read -r -p "请按回车继续..." _;;
    3) stop_panel; read -r -p "请按回车继续..." _;;
    4) show_address; read -r -p "请按回车继续..." _;;
    5) show_credentials; read -r -p "请按回车继续..." _;;
    6) reset_password; read -r -p "请按回车继续..." _;;
    0) exit;;
    *) say "无效选择。";;
  esac
done
