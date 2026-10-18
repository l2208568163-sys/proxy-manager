#!/usr/bin/env bash
#
# server-fix-proxy.sh
# 修复 Ubuntu 服务器上 `proxy` 命令被系统程序 /usr/bin/proxy 抢占、导致菜单空白、
# 回车出 direct:// 的问题。方案 A：只把 proxy 命令指回老版中文 v3 项目，不动服务。
#
# 用法（在服务器上，需 root）：
#   bash server-fix-proxy.sh
#
set -euo pipefail

# 项目根目录（老版中文 v3 所在位置，按需修改）
PROXY_MANAGER_DIR="${PROXY_MANAGER_DIR:-/opt/proxy-manager}"

WRAPPER="/usr/local/bin/proxy"

echo "==> 项目目录: $PROXY_MANAGER_DIR"

# ---- 1. 定位主脚本（老版 v3：菜单用 case \$num / 请选择，可能带 proxy-manager/ 子目录）----
TARGET=""
if [[ -f "$PROXY_MANAGER_DIR/proxy-manager.sh" ]]; then
  TARGET="$PROXY_MANAGER_DIR/proxy-manager.sh"
elif [[ -f "$PROXY_MANAGER_DIR/proxy-manager/proxy-manager.sh" ]]; then
  TARGET="$PROXY_MANAGER_DIR/proxy-manager/proxy-manager.sh"
else
  # 退而求其次：在目录里找第一个含菜单特征标记的 .sh
  TARGET="$(find "$PROXY_MANAGER_DIR" -maxdepth 2 -name '*.sh' \
            -exec grep -l '请选择\|case \$num\|case \$choice' {} + 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$TARGET" || ! -f "$TARGET" ]]; then
  echo "错误：未在 $PROXY_MANAGER_DIR 下找到 Proxy Manager 主脚本。" >&2
  echo "请手动确认主脚本路径，并设置环境变量后重试：" >&2
  echo "  PROXY_MANAGER_DIR=/实际/路径 bash server-fix-proxy.sh" >&2
  exit 1
fi
echo "==> 找到主脚本: $TARGET"

# ---- 2. 写入包装脚本 ----
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# Proxy Manager 命令包装（自动生成，请勿手动编辑）
set -euo pipefail
TARGET="$TARGET"
if [[ ! -f "\$TARGET" ]]; then
  echo "错误：Proxy Manager 主脚本丢失: \$TARGET" >&2
  exit 1
fi
exec bash "\$TARGET" "\$@"
EOF

chmod +x "$WRAPPER"
echo "==> 已写入并赋值可执行: $WRAPPER"

# ---- 3. 处理 PATH 抢占：确保 /usr/local/bin 在 /usr/bin 之前 ----
if ! [[ ":$PATH:" == *":/usr/local/bin:"* ]] || \
   [[ "$(echo "$PATH" | tr ':' '\n' | grep -n '^/usr/local/bin$' | head -n1 | cut -d: -f1)" -gt \
      "$(echo "$PATH" | tr ':' '\n' | grep -n '^/usr/bin$' | head -n1 | cut -d: -f1)" ]]; then
  echo "==> 检测到 /usr/local/bin 未在 /usr/bin 之前，写入 /etc/profile.d/proxy-path.sh"
  cat > /etc/profile.d/proxy-path.sh <<'EOP'
# 保证项目 proxy 命令优先于系统同名程序
case ":$PATH:" in
  *":/usr/local/bin:"*) ;;
  *) export PATH="/usr/local/bin:$PATH" ;;
esac
EOP
  chmod +x /etc/profile.d/proxy-path.sh
  # 当前 shell 立即生效
  export PATH="/usr/local/bin:$PATH"
fi

# ---- 4. 清除 bash 哈希缓存并校验 ----
hash -r
echo "==> 校验 type proxy:"
type proxy
echo
echo "完成。现在直接输入 proxy 即可打开 Proxy Manager 菜单。"
echo "若仍显示 /usr/bin/proxy，请重新登录终端（让 /etc/profile.d 生效）后再试。"
