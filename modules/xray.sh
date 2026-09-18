#!/bin/bash

BASE="/opt/proxy-manager"
DATA="$BASE/data/node.env"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

install_xray(){
    echo "Installing Xray Reality..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    UUID=$(xray uuid)
    KEYS=$(xray x25519)

    PRIVATE_KEY=$(echo "$KEYS" | grep '^PrivateKey:' | awk -F': ' '{print $2}')
    PUBLIC_KEY=$(echo "$KEYS" | grep '^Password (PublicKey):' | awk -F': ' '{print $2}')

    if [ -z "$PUBLIC_KEY" ]; then
        PUBLIC_KEY=$(echo "$KEYS" | grep '^Password:' | awk -F': ' '{print $2}')
    fi

    SHORT_ID=$(openssl rand -hex 8)
    SERVER=$(curl -4 -s https://api.ipify.org)

    mkdir -p /usr/local/etc/xray

    cat > "$XRAY_CONFIG" <<EOF
{
 "inbounds":[{
  "port":443,
  "protocol":"vless",
  "settings":{"clients":[{"id":"$UUID","flow":"xtls-rprx-vision"}],"decryption":"none"},
  "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"www.cloudflare.com:443","serverNames":["www.cloudflare.com"],"privateKey":"$PRIVATE_KEY","shortIds":["$SHORT_ID"]}}
 }],
 "outbounds":[{"protocol":"freedom"}]
}
EOF

    mkdir -p "$BASE/data"
    cat > "$DATA" <<EOF
SERVER=$SERVER
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
PORT=443
SNI=www.cloudflare.com
EOF

    systemctl enable xray
    systemctl restart xray

    echo "Xray Reality installed"
}

menu(){
while true; do
clear
echo "1.Install Xray"
echo "2.Restart Xray"
echo "3.Status"
echo "0.Back"
read -p "Choose:" C
case $C in
1) install_xray;;
2) systemctl restart xray;;
3) systemctl status xray;;
0) exit;;
esac
done
}

menu
