#!/bin/bash

BASE="/opt/proxy-manager"

while true; do
clear
echo "================================"
echo " Proxy Manager v3.1"
echo "================================"
echo "1. Xray Reality"
echo "2. Clash Subscription"
echo "3. Mihomo"
echo "4. DNS"
echo "5. System Optimization"
echo "6. View Node"
echo "7. Uninstall"
echo "0. Exit"
read -p "Select: " N

case $N in
1) bash $BASE/modules/xray.sh ;;
2) bash $BASE/modules/subscription.sh ;;
3) bash $BASE/modules/mihomo.sh ;;
4) bash $BASE/modules/dns.sh ;;
5) bash $BASE/modules/system.sh ;;
6) cat $BASE/data/node.env 2>/dev/null; read -p "Enter" ;;
7) rm -rf $BASE; echo "Removed"; exit ;;
0) exit ;;
esac
done
