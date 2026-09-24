#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
install_mihomo() {
  local platform asset json tmp bin
  case "$(uname -m)" in x86_64|amd64) platform=amd64;; aarch64|arm64) platform=arm64;; armv7l|armv7) platform=armv7;; *) die "Unsupported CPU architecture.";; esac
  # GitHub 匿名 API 每小时限 60 次（NAT 共享出口 IP 的机器易触顶）；设置 GITHUB_TOKEN 可提升限额
  local -a auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then auth_args=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
  json="$(curl -fsSL --max-time 30 "${auth_args[@]}" https://api.github.com/repos/MetaCubeX/mihomo/releases/latest)" \
    || die "获取 mihomo 版本信息失败（GitHub API 可能限流或网络不通；可设置 GITHUB_TOKEN 后重试）。"
  # 显式选版，不依赖 API 返回顺序：
  #   1) 标准构建 mihomo-linux-<平台>-v<版本>.gz（跳过需要较新 CPU 的 -v3- 与 -compatible- 变体）
  #   2) 回退 -compatible- 构建（兼容老 CPU）
  asset="$(jq -r --arg p "mihomo-linux-$platform" '
    ([.assets[].browser_download_url
      | select(test("/" + $p + "-v[0-9][0-9.]*\\.gz$"))][0]
     // ([.assets[].browser_download_url
      | select(test("/" + $p + "-compatible-v[0-9][0-9.]*\\.gz$"))][0]
     // ""))' <<<"$json")"
  [[ -n "$asset" ]] || die "未在最新 Release 中找到适用于 $platform 的 mihomo 下载项。"
  tmp="$(mktemp)"; trap 'rm -f "$tmp" ${bin:+"$bin"}' RETURN
  curl -fL --max-time 300 "$asset" -o "$tmp" || die "下载 mihomo 失败：$asset"
  # 完整性自检：gzip 结构校验 + 安装后实际运行一次
  gzip -t "$tmp" 2>/dev/null || die "下载的 mihomo 压缩包损坏（gzip 校验失败），请重试。"
  bin="$(mktemp)"; gzip -dc "$tmp" >"$bin"
  install -m 0755 "$bin" /usr/local/bin/mihomo
  mihomo -v >/dev/null 2>&1 || die "mihomo 二进制无法运行（构建可能与本机 CPU 不兼容）。"
  say "已安装: $(mihomo -v 2>&1 | head -n1)"
  install -d -m 0755 "$MIHOMO_DIR"
  cat >/etc/systemd/system/mihomo.service <<'EOF'
[Unit]
Description=Mihomo Proxy Client
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; say "Mihomo 已安装。启动前请先导入订阅。"
}
import_config() {
  local url tmp; read -r -p "请输入 Mihomo 订阅 URL: " url; [[ "$url" =~ ^https?:// ]] || die "订阅地址必须以 http:// 或 https:// 开头"
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN; curl -fsSL --max-time 30 "$url" -o "$tmp"; mihomo -t -f "$tmp" >/dev/null
  install -d -m 0755 "$MIHOMO_DIR"; install -m 0600 "$tmp" "$MIHOMO_CONFIG"; systemctl enable --now mihomo; say "Mihomo 已启动。"
}
enable_tun() {
  [[ -f "$MIHOMO_CONFIG" ]] || die "Import a subscription before enabling TUN."
  grep -Eq '^tun:' "$MIHOMO_CONFIG" && die "该配置已定义 TUN，请直接编辑原配置，不要重复添加 TUN 段。"
  cat >>"$MIHOMO_CONFIG" <<'EOF'

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  dns-hijack:
    - any:53
    - tcp://any:53
EOF
  mihomo -t -f "$MIHOMO_CONFIG" >/dev/null
  systemctl restart mihomo
  say "TUN 模式已启用。它会修改主机路由表；如需关闭，请恢复原订阅配置。"
}
require_root
while true; do clear; say "===== Mihomo 客户端 ====="; say "1. 安装或更新核心"; say "2. 导入订阅并启动"; say "3. 为已导入配置启用 TUN 模式"; say "4. 重启"; say "5. 状态"; say "0. 返回"; read -r -p "请选择: " c; case "$c" in 1) install_mihomo; read -r -p "请按回车继续..." _;;2) require_command mihomo; import_config; read -r -p "请按回车继续..." _;;3) require_command mihomo; enable_tun; read -r -p "请按回车继续..." _;;4) systemctl restart mihomo;;5) systemctl --no-pager status mihomo || true; read -r -p "请按回车继续..." _;;0) exit;;*) say "无效选择。";;esac; done
