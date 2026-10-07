#!/usr/bin/env bash
#################################################
# Proxy Manager v3.4.1 —— 完整卸载 (Clean Uninstall)
#
# 用法:
#   bash uninstall.sh           普通卸载（保留 data/ 便于重装）
#   bash uninstall.sh --clean   完全清理（连 data/ 节点密钥一起删）
#   bash uninstall.sh --help    查看帮助
#
# 卸载收尾会列出 /opt/proxy-manager-backup-* 历史备份，
# 由用户决定「全部保留 / 全部删除 / 按编号删除」。
#
# 注意：本脚本刻意不依赖 lib/common.sh，即便项目其他脚本损坏也能独立卸载。
#################################################

GREEN='\033[32m'; RED='\033[31m'; YEL='\033[33m'; NC='\033[0m'
info()  { printf "${GREEN}[%s] %s${NC}\n" "$1" "$2"; }
warn()  { printf "${YEL}[%s] %s${NC}\n" "$1" "$2"; }

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---- 参数解析 ----
CLEAN=0
case "${1:-}" in
  --clean) CLEAN=1;;
  --help|-h) echo "用法: bash uninstall.sh [--clean]"; echo "  --clean  额外删除 data/（节点密钥）"; exit 0;;
  "") ;;
  *) echo "未知参数: $1"; exit 1;;
esac

# ---- 权限检查 ----
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "错误: 请使用 root 权限运行（sudo bash uninstall.sh）。"
  exit 1
fi

echo
echo "==================================="
echo "  Proxy Manager 完整卸载 v3.4.1"
echo "==================================="
warn "模式" "$([ "$CLEAN" -eq 1 ] && echo '完全清理（含 data/ 节点密钥）' || echo '普通卸载（保留 data/ 便于重装）')"
echo

read -r -p "确认完全卸载 Proxy Manager ? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "已取消卸载。"
  exit 0
fi

# ---- 1/9 停止并禁用服务 ----
info "1/9" "停止并禁用相关服务"
SERVICES=(xray nginx fail2ban)
for s in "${SERVICES[@]}"; do
  systemctl stop   "$s" 2>/dev/null || true
  systemctl disable "$s" 2>/dev/null || true
done

# ---- 2/9 删除 systemd 单元 ----
info "2/9" "删除 systemd 服务单元"
rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray.service.d
systemctl daemon-reload 2>/dev/null || true

# ---- 3/9 删除 Xray ----
info "3/9" "删除 Xray"
rm -rf /usr/local/bin/xray /usr/local/etc/xray

# ---- 4/9 删除 Nginx 订阅站点 ----
info "4/9" "删除 Nginx 订阅配置"
rm -f /etc/nginx/sites-enabled/proxy-manager.conf \
      /etc/nginx/sites-available/proxy-manager.conf
# proxy-manager.conf 曾接管 :80 default_server，这里恢复发行版默认站点
if [[ -f /etc/nginx/sites-available/default && -d /etc/nginx/sites-enabled \
      && ! -e /etc/nginx/sites-enabled/default && ! -L /etc/nginx/sites-enabled/default ]]; then
  ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi
rm -rf /var/www/html/clash
nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true

# ---- 5/9 清理防火墙规则 ----
info "5/9" "清理防火墙规则"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  for p in 443 80 7890; do
    ufw delete allow "${p}/tcp" 2>/dev/null || true
  done
fi

# ---- 6/9 恢复网络优化（BBR / FQ / TFO）----
info "6/9" "恢复网络优化"
rm -f /etc/sysctl.d/99-proxy-manager.conf
# 项目专属文件已删；若用户在 /etc/sysctl.conf 里手动留过 bbr/fq/tcp_fastopen，提示确认删除
if grep -Eq 'bbr|fq|tcp_fastopen' /etc/sysctl.conf 2>/dev/null; then
  warn "检测" "/etc/sysctl.conf 中可能存在手动残留的网络优化参数："
  grep -En 'bbr|fq|tcp_fastopen' /etc/sysctl.conf
  read -r -p "是否删除以上行？(y/N): " DELSYSCONF
  if [[ "$DELSYSCONF" =~ ^[Yy] ]]; then
    sed -i '/bbr\|fq\|tcp_fastopen/d' /etc/sysctl.conf
  fi
fi
sysctl --system >/dev/null 2>&1 || true

# ---- 7/9 还原端口 53 占用（WiFi 跳验证节点可能关闭过 systemd-resolved 的 stub 监听）----
info "7/9" "还原 systemd-resolved 端口 53 配置"
rm -f /etc/systemd/resolved.conf.d/proxy-manager-port53.conf
if [[ -f /etc/resolv.conf.bak.proxy-manager ]]; then
  mv -f /etc/resolv.conf.bak.proxy-manager /etc/resolv.conf
fi
systemctl restart systemd-resolved 2>/dev/null || true

# ---- 8/9 删除项目文件 / 命令 ----
info "8/9" "删除项目文件与命令"
rm -f /usr/local/bin/proxy
if [[ "$CLEAN" -eq 1 ]]; then
  rm -rf "$BASE_DIR"
else
  # 普通模式：删除除 data/ 以外的全部内容，保留节点数据便于重装
  find "$BASE_DIR" -mindepth 1 -maxdepth 1 ! -name data -exec rm -rf {} +
  warn "保留" "$BASE_DIR/data 已保留（含节点密钥），重装时可直接复用"
fi

# ---- 9/9 处理历史备份（install.sh 生成的 /opt/proxy-manager-backup-*）----
info "9/9" "处理历史备份"
BK_LIST=()
while IFS= read -r d; do [[ -n "$d" ]] && BK_LIST+=("$d"); done < <(ls -1dt /opt/proxy-manager-backup-* 2>/dev/null || true)

if (( ${#BK_LIST[@]} == 0 )); then
  info "备份" "未发现历史备份目录（/opt/proxy-manager-backup-*），跳过"
else
  echo
  warn "备份" "检测到 ${#BK_LIST[@]} 个历史备份（含节点密钥 data/，删除后不可恢复）："
  i=1
  for d in "${BK_LIST[@]}"; do
    sz="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
    printf '  %d) %s   [大小: %s | 时间: %s]\n' \
      "$i" "$d" "${sz:-未知}" "$(date -r "$d" '+%F %T' 2>/dev/null || echo '-')"
    i=$((i+1))
  done
  echo
  echo "  a = 全部删除     n = 全部保留     s = 按编号选择删除（例如输入: 1 3）"
  echo
  read -r -p "卸载后是否删除这些备份？[a/N/s]: " BK_ANS || BK_ANS=""
  BK_ANS="$(printf '%s' "${BK_ANS:-}" | tr '[:upper:]' '[:lower:]')"
  case "$BK_ANS" in
    a|all)
      for d in "${BK_LIST[@]}"; do rm -rf "$d"; done
      info "备份" "已删除全部 ${#BK_LIST[@]} 个备份目录"
      ;;
    s|sel)
      read -r -p "输入要删除的编号（空格分隔，如: 1 3）: " BK_PICKS || BK_PICKS=""
      for n in ${BK_PICKS:-}; do
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#BK_LIST[@]} )); then
          rm -rf "${BK_LIST[$((n-1))]}"
          info "备份" "已删除 ${BK_LIST[$((n-1))]}"
        else
          warn "备份" "忽略无效编号: $n"
        fi
      done
      ;;
    *)
      info "备份" "已保留全部备份目录："
      for d in "${BK_LIST[@]}"; do echo "       $d"; done
      echo "       提示：下次运行 install.sh 时会再次询问是否从中恢复；"
      echo "       也可随时手动 rm -rf 删除。"
      ;;
  esac
fi

# ---- 完全清理模式下，询问是否卸载我们装过的 apt 包 ----
if [[ "$CLEAN" -eq 1 ]]; then
  read -r -p "是否一并卸载 fail2ban / unattended-upgrades / nginx（若由本项目安装）? (y/N): " PURGE
  if [[ "$PURGE" =~ ^[Yy] ]]; then
    apt-get purge -y fail2ban unattended-upgrades nginx 2>/dev/null || true
  fi
fi

echo
echo "==================================="
echo " 卸载完成"
echo " 建议重启服务器以彻底释放资源："
echo "   reboot"
echo "==================================="
