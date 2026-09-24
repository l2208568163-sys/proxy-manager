#!/usr/bin/env bash
####################################################
#
# Proxy-Manager v3.2.2
# Installation Script
#
####################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(<"$SCRIPT_DIR/VERSION")"
INSTALL_DIR="${INSTALL_DIR:-/opt/proxy-manager}"
REPO_URL="${REPO_URL:-https://github.com/l2208568163-sys/proxy-manager.git}"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
NC="\033[0m"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

command -v clear >/dev/null 2>&1 && clear
echo "
========================================

     Proxy-Manager Installer

             v${VERSION}

========================================
"

####################################################
# Root Check
####################################################
[[ $EUID -eq 0 ]] || error "请使用 root 运行"

####################################################
# OS Check
####################################################
info "检测系统"
[[ -f /etc/os-release ]] || error "无法识别系统 (缺少 /etc/os-release)"
# shellcheck disable=SC1091
source /etc/os-release
case "$ID" in
  ubuntu|debian) ;;
  *) warn "当前系统 $ID 未经测试，继续但可能失败" ;;
esac
echo "System: ${PRETTY_NAME:-unknown}"

####################################################
# Architecture Check
####################################################
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) info "架构: $ARCH" ;;
  *) error "不支持的架构: $ARCH（仅支持 x86_64 / aarch64）" ;;
esac

####################################################
# Parse args / update prompt
####################################################
UPDATE_SYS=false
case "${1:-}" in
  --update-system) UPDATE_SYS=true ;;
  --help|-h) echo "Usage: bash install.sh [--update-system]"; exit 0 ;;
  "") ;;
  *) error "未知参数: ${1}（用法: bash install.sh [--update-system]）" ;;
esac
if [[ "$UPDATE_SYS" == false && -t 0 ]]; then
  read -r -p "是否更新系统软件源? (y/n): " ans
  [[ "$ans" =~ ^[Yy] ]] && UPDATE_SYS=true
fi

####################################################
# Update apt index (always) / Upgrade system (optional)
####################################################
export DEBIAN_FRONTEND=noninteractive
# 无条件刷新索引：全新机器列表为空时，跳过这步 apt-get install 会直接失败
info "更新软件源索引"
apt-get update
if [[ "$UPDATE_SYS" == true ]]; then
  info "升级系统软件包"
  apt-get upgrade -y
fi

####################################################
# Install Dependencies
####################################################
info "安装依赖"
apt-get install -y --no-install-recommends \
  ca-certificates curl wget git gzip tar jq openssl \
  iproute2 ufw nginx python3 python3-pip python3-venv net-tools

####################################################
# Backup Existing (keep node data)
####################################################
BACKUP=""
if [[ -d "$INSTALL_DIR" ]]; then
  info "发现旧安装，备份数据"
  BACKUP="/opt/proxy-manager-backup-$(date +%Y%m%d-%H%M)"
  mkdir -p "$BACKUP"
  [[ -d "$INSTALL_DIR/data" ]] && cp -r "$INSTALL_DIR/data" "$BACKUP/" 2>/dev/null || true
  echo "备份目录: $BACKUP"
fi

####################################################
# Download / Update Project
####################################################
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "更新项目 (git pull --ff-only)"
  git -C "$INSTALL_DIR" pull --ff-only
else
  if [[ -e "$INSTALL_DIR" ]]; then
    warn "$INSTALL_DIR 不是 Git 仓库，将被覆盖（数据已备份至 $BACKUP）"
    rm -rf "$INSTALL_DIR"
  fi
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  # 还原节点数据（仅替换安装时）
  if [[ -n "$BACKUP" && -d "$BACKUP/data" ]]; then
    cp -r "$BACKUP/data/." "$INSTALL_DIR/data/" 2>/dev/null || true
    info "已从备份恢复节点数据"
  fi
fi

####################################################
# Directory Permission
####################################################
info "创建目录与权限"
install -d -m 0700 "$INSTALL_DIR/data"
install -d -m 0755 "$INSTALL_DIR/logs"

####################################################
# Install Web Dashboard (auto, best-effort)
####################################################
if [[ -f "$INSTALL_DIR/modules/webpanel.sh" ]]; then
  info "安装 Web 管理面板"
  bash "$INSTALL_DIR/modules/webpanel.sh" install || warn "Web 面板安装失败，可稍后运行 proxy 主菜单 12 重新安装"
fi

####################################################
# Install Command (dynamic path)
####################################################
info "创建管理命令 /usr/local/bin/proxy"
cat >/usr/local/bin/proxy <<PROXYEOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/proxy-manager.sh" "\$@"
PROXYEOF
chmod 0755 /usr/local/bin/proxy

####################################################
# Permissions
####################################################
find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 0755 {} +

####################################################
# Firewall
####################################################
info "配置防火墙放行规则"
# 8080（Web 面板）不放行：面板默认仅监听 127.0.0.1，公网访问需在面板菜单显式开启
for p in 22 80 443; do
  ufw allow "${p}/tcp" >/dev/null 2>&1 || true
done

####################################################
# Systemd Reload
####################################################
systemctl daemon-reload >/dev/null 2>&1 || true

####################################################
# Finish
####################################################
echo "
========================================
安装完成

目录:   $INSTALL_DIR
命令:   proxy
版本:   $VERSION
"
if [[ -f "$INSTALL_DIR/data/web.env" ]]; then
  # shellcheck disable=SC1090
  source "$INSTALL_DIR/data/web.env"
  IP="$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo '<服务器IP>')"
  echo
  echo "账号: ${WEB_USER:-admin}（密码见 $INSTALL_DIR/data/web.env）"
  if [[ "${WEB_BIND:-127.0.0.1}" == "0.0.0.0" ]]; then
    echo "Web 控制台: http://$IP:8080（公网暴露中，建议加反向代理或仅 SSH 隧道访问）"
  else
    echo "Web 控制台: 默认仅本机监听 127.0.0.1:8080"
    echo "  访问方式: ssh -L 8080:127.0.0.1:8080 用户@$IP 后打开 http://localhost:8080"
    echo "  公网访问: proxy → 12 → 7 开启『公网访问开关』"
  fi
fi
echo
echo "下一步: 运行 proxy 打开主菜单；选 1 生成 Xray 节点、选 2 生成 Clash 订阅、选 12 管理 Web 面板"
echo "========================================
"
