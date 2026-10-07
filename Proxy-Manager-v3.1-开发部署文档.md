# Proxy Manager 开发部署文档（v3.1 历史版）

> 说明：本文档为 v3.1 时期的开发部署说明，仅作历史参考。后续版本已移除 Web 管理面板（v3.3.0），以及整个 DNS 模块（含 AdGuard Home）与 Mihomo 客户端模块（v3.4.0），modules/dns.sh、modules/mihomo.sh 均已删除。

## 项目简介

Proxy Manager 是一个基于 Ubuntu 的代理服务自动化管理项目。

目标：

-   Xray Reality 节点自动部署
-   Clash URL订阅生成
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

# Mihomo（已移除）

> 注：Mihomo 客户端模块（原 modules/mihomo.sh）已在 v3.4.0 移除，本段仅供历史参考。

------------------------------------------------------------------------

# DNS（已移除）

> 注：DNS 模块（AdGuard Home + 系统 DNS 优化，原 modules/dns.sh）已在 v3.4.0 移除，本段仅供历史参考。

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

------------------------------------------------------------------------

# 后续扩展

计划：

-   Web管理面板
-   多节点管理
-   用户管理
-   自动HTTPS
-   Telegram通知
