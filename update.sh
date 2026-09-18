#!/bin/bash

BASE="/opt/proxy-manager"

VERSION_FILE="$BASE/VERSION"


echo "
================================
 Proxy Manager Update
================================
"


if [ ! -d "$BASE" ];then

echo "未检测到安装目录"

exit 1

fi


cd $BASE



echo "[1] 当前版本"

cat VERSION_FILE



echo ""

echo "[2] 拉取最新代码"


git pull



echo ""

echo "[3] 重启服务"



systemctl restart xray 2>/dev/null


systemctl restart mihomo 2>/dev/null


systemctl restart nginx 2>/dev/null



echo "

更新完成

"
