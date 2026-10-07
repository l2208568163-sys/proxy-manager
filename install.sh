#!/usr/bin/env bash
####################################################
#
# Proxy-Manager v3.4.3
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
# restore 策略：ask = 有终端就问、无终端自动恢复最新；never = 不恢复；always = 直接恢复最新
RESTORE_MODE="ask"
case "${1:-}" in
  --update-system) UPDATE_SYS=true ;;
  --no-restore)    RESTORE_MODE="never" ;;
  --restore)       RESTORE_MODE="always" ;;
  --help|-h)
    echo "Usage: bash install.sh [--update-system] [--no-restore] [--restore]"
    echo "  --update-system   顺带 apt-get upgrade 升级系统软件包"
    echo "  --restore         不经确认，直接恢复最新备份的节点数据"
    echo "  --no-restore      不恢复任何备份，使用全新节点数据（保留历史备份目录）"
    exit 0 ;;
  "") ;;
  *) error "未知参数: ${1}（用法: bash install.sh [--update-system] [--no-restore] [--restore]）" ;;
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
    warn "$INSTALL_DIR 不是 Git 仓库，将被覆盖（数据已备份至 ${BACKUP:-无}）"
    rm -rf "$INSTALL_DIR"
  fi
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

####################################################
# Restore backup (由用户决定是否恢复，不再自动恢复)
####################################################
# 备份来源：本次安装前生成的，以及历史遗留的 /opt/proxy-manager-backup-*
BACKUP_LIST=()
while IFS= read -r d; do BACKUP_LIST+=("$d"); done < <(ls -1dt /opt/proxy-manager-backup-* 2>/dev/null || true)

if (( ${#BACKUP_LIST[@]} )); then
  echo
  info "备份" "检测到以下备份目录："
  idx=1
  for d in "${BACKUP_LIST[@]}"; do
    tag=""
    [[ "$d" == "$BACKUP" ]] && tag="（本次安装前生成）"
    printf '  %d) %s%s\n' "$idx" "$d" "$tag"
    idx=$((idx+1))
  done
  echo "  0) 不恢复，使用全新配置"
  echo
  warn "备份" "恢复会用备份中的文件覆盖 $INSTALL_DIR/data 下的同名文件（节点密钥将被替换）。"
  echo
  RESTORE_DIR=""
  if [[ "$RESTORE_MODE" == "never" ]]; then
    info "备份" "已指定 --no-restore：不恢复，使用全新节点数据（备份目录仍保留在 /opt 下）"
  elif [[ "$RESTORE_MODE" == "always" ]]; then
    RESTORE_DIR="${BACKUP_LIST[0]}"
    info "备份" "已指定 --restore：从最新备份 $RESTORE_DIR 恢复节点数据"
  elif [[ -t 0 ]]; then
    # 仅在有终端时询问；非交互（如 curl ... | bash）时 stdin 是脚本本身，
    # 直接 read 会把脚本后续内容当输入吃掉，必须跳过。
    read -r -p "是否从备份恢复节点数据？请输入编号 [0]: " pick || pick=""
    pick="${pick:-0}"
    if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#BACKUP_LIST[@]} )); then
      RESTORE_DIR="${BACKUP_LIST[$((pick-1))]}"
    else
      info "备份" "未选择备份，将使用全新节点数据"
    fi
  else
    # 非交互模式沿用旧行为：自动恢复最新备份（本次安装前生成的优先），保证节点不丢
    RESTORE_DIR="${BACKUP_LIST[0]}"
    info "备份" "非交互模式：自动从最新备份 $RESTORE_DIR 恢复节点数据"
  fi

  if [[ -n "$RESTORE_DIR" ]]; then
    if [[ -d "$RESTORE_DIR/data" ]]; then
      install -d -m 0700 "$INSTALL_DIR/data"
      cp -r "$RESTORE_DIR/data/." "$INSTALL_DIR/data/" 2>/dev/null || true
      info "备份" "已从 $RESTORE_DIR 恢复节点数据"
    else
      warn "备份" "$RESTORE_DIR 中没有 data/，未恢复任何节点数据"
    fi
  else
    info "备份" "未恢复备份，将使用全新节点数据"
  fi
fi

####################################################
# Directory Permission
####################################################
info "创建目录与权限"
install -d -m 0700 "$INSTALL_DIR/data"
install -d -m 0755 "$INSTALL_DIR/logs"

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
echo
echo "下一步: 运行 proxy 打开主菜单；选 1 生成 Xray 节点、选 2 生成 Clash 订阅"
echo "========================================
"
