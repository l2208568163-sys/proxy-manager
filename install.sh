#!/usr/bin/env bash
set -Eeuo pipefail
REPO_URL="${REPO_URL:-https://github.com/l2208568163-sys/proxy-manager.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/proxy-manager}"
UPDATE_SYSTEM=false
case "${1:-}" in --update-system) UPDATE_SYSTEM=true;; --help|-h) echo "Usage: bash install.sh [--update-system]"; exit 0;; "") ;; *) exit 2;; esac
[[ $EUID -eq 0 ]] || { echo "Please run as root." >&2; exit 1; }
if [[ -t 0 && "$UPDATE_SYSTEM" == false ]]; then read -r -p "Update system packages first? [y/N]: " a; [[ "$a" =~ ^[Yy]([Ee][Ss])?$ ]] && UPDATE_SYSTEM=true; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
[[ "$UPDATE_SYSTEM" == true ]] && apt-get upgrade -y
apt-get install -y ca-certificates curl git gzip iproute2 jq nginx openssl tar ufw python3 python3-venv
if [[ -e "$INSTALL_DIR" ]]; then
  git -C "$INSTALL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Refusing to overwrite non-Git directory: $INSTALL_DIR" >&2; exit 1; }
  git -C "$INSTALL_DIR" pull --ff-only
else git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; fi
install -d -m 0755 "$INSTALL_DIR/data" /var/www/html/clash
find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
cat >/usr/local/bin/proxy <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/proxy-manager.sh" "\$@"
EOF
chmod 0755 /usr/local/bin/proxy
echo "Installation completed. Run: proxy"
