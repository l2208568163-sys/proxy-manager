#!/bin/bash


install_web(){


apt install nginx -y



mkdir -p /var/www/html/clash



cat >/etc/nginx/sites-enabled/proxy-manager.conf <<EOF

server {


listen 80;


server_name _;



location /clash {


alias /var/www/html/clash;


autoindex on;


}


}

EOF



nginx -t && systemctl restart nginx



echo "Web订阅服务完成"


}



menu(){


install_web

}

menu
