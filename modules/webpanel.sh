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
  python3 -m venv "$WEB_DIR/venv"
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

require_root
while true; do
  clear; say "===== Web 管理面板 ====="; say "1. 安装并启动面板"; say "2. 查看状态"; say "3. 重启面板"; say "0. 返回"
  read -r -p "请选择: " c
  case "$c" in
    1) install_panel; read -r -p "请按回车继续..." _;;
    2) systemctl --no-pager status proxy-web || true; read -r -p "请按回车继续..." _;;
    3) systemctl restart proxy-web;;
    0) exit;;
    *) say "无效选择。";;
  esac
done
