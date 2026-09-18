#!/bin/bash

BASE="/opt/proxy-manager"
DATA="$BASE/data/node.env"
WEB="/var/www/html/clash"

source "$DATA" 2>/dev/null

generate(){
mkdir -p "$WEB"

cat > "$WEB/config.yaml" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
proxies:
  - name: Reality-$SERVER
    type: vless
    server: $SERVER
    port: $PORT
    uuid: $UUID
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: $SNI
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
    client-fingerprint: chrome
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Reality-$SERVER
      - DIRECT
rules:
  - MATCH,Proxy
EOF

echo "Clash subscription:"
echo "http://$SERVER/clash/config.yaml"
}

case "$1" in
generate) generate;;
*) generate;;
esac
