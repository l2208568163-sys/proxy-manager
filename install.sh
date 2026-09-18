#!/bin/bash
set -e

INSTALL_DIR="/opt/proxy-manager"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

read -p "Update system packages? (y/n): " UPDATE
if [ "$UPDATE" = "y" ]; then
  apt update -y
  apt upgrade -y
fi

apt install -y curl wget git nginx openssl ufw

mkdir -p "$INSTALL_DIR"/{modules,data}
mkdir -p /var/www/html/clash

cp proxy-manager.sh "$INSTALL_DIR/" 2>/dev/null || true
cp modules/*.sh "$INSTALL_DIR/modules/" 2>/dev/null || true

chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/modules/*.sh 2>/dev/null || true

cat >/usr/local/bin/proxy <<EOF
#!/bin/bash
bash /opt/proxy-manager/proxy-manager.sh
EOF
chmod +x /usr/local/bin/proxy

systemctl enable nginx
systemctl restart nginx

echo "Installation completed. Run: proxy"
