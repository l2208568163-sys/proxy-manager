#!/bin/bash


echo "

============================

Proxy Manager Health Check

============================

"



check(){


if systemctl is-active --quiet $1

then

echo "[OK] $1"

else

echo "[FAIL] $1"

fi


}



check xray

check mihomo

check nginx



echo ""

echo "端口检查"



ss -lntp | grep -E "443|80|7890"



echo ""

echo "节点文件"



if [ -f /opt/proxy-manager/data/node.env ]

then

echo "[OK] node.env"

else

echo "[FAIL] node.env"

fi

