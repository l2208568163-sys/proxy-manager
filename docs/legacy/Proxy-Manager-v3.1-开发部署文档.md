# Proxy Manager v3.1 开发部署文档

## 项目简介

Proxy Manager v3.1 是一个基于 Ubuntu 的代理服务自动化管理项目。

目标：

-   Xray Reality 节点自动部署
-   Mihomo(Clash Meta)管理
-   Clash URL订阅生成
-   DNS优化
-   BBR/TCP网络优化
-   GitHub版本管理

------------------------------------------------------------------------

# 项目结构

``` text
proxy-manager-v3/

├── install.sh
├── proxy-manager.sh

├── modules/
│   ├── xray.sh
│   ├── subscription.sh
│   ├── mihomo.sh
│   ├── dns.sh
│   └── system.sh

└── data/
    └── node.env
```

------------------------------------------------------------------------

# 安装

``` bash
bash install.sh
```

安装完成：

``` bash
proxy
```

进入管理菜单。

------------------------------------------------------------------------

# Xray Reality

功能：

-   自动安装 Xray
-   自动生成 UUID
-   自动生成 Reality Key
-   自动生成节点信息

节点保存：

``` text
/opt/proxy-manager/data/node.env
```

示例：

``` text
SERVER=服务器IP
UUID=UUID
PRIVATE_KEY=PrivateKey
PUBLIC_KEY=PublicKey
SHORT_ID=ShortID
```

------------------------------------------------------------------------

# Clash URL订阅

系统生成：

``` text
http://服务器IP/clash/config.yaml
```

Clash Verge:

配置文件 -\> 新建订阅 -\> 粘贴URL

即可自动导入。

------------------------------------------------------------------------

# Mihomo

支持：

-   Clash Meta
-   TUN模式
-   Fake-IP DNS
-   自动路由

配置：

``` text
/etc/mihomo/config.yaml
```

------------------------------------------------------------------------

# DNS

支持：

-   AdGuard Home
-   DoH
-   DNS优化

------------------------------------------------------------------------

# 系统优化

支持：

-   BBR
-   TCP Fast Open
-   防火墙规则

检查BBR：

``` bash
sysctl net.ipv4.tcp_congestion_control
```

返回：

``` text
bbr
```

表示开启。

------------------------------------------------------------------------

# GitHub部署

初始化：

``` bash
git init
git add .
git commit -m "Proxy Manager v3.1"
```

上传：

``` bash
git push origin main
```

------------------------------------------------------------------------

# 故障排查

## Clash订阅为空

检查：

``` bash
cat /opt/proxy-manager/data/node.env
```

确认：

-   PUBLIC_KEY存在
-   UUID存在
-   SERVER存在

## Xray状态

``` bash
systemctl status xray
```

## Mihomo状态

``` bash
systemctl status mihomo
```

------------------------------------------------------------------------

# 后续扩展

计划：

-   Web管理面板
-   多节点管理
-   用户管理
-   自动HTTPS
-   Telegram通知
