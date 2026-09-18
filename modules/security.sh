#!/bin/bash


install_security(){


echo "安装安全组件"


apt update


apt install fail2ban unattended-upgrades -y



systemctl enable fail2ban


systemctl start fail2ban



echo "安全模块完成"

}



status_security(){


systemctl status fail2ban


}



menu(){


while true

do


echo "

================

安全管理

================


1. 安装安全模块

2. 查看状态

0. 返回


"



read -p "选择:" n



case $n in


1)

install_security

;;


2)

status_security

;;


0)

return

;;


esac


done


}


menu
