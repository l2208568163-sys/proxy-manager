# 🚀 Proxy-Manager

<p align="center">
  <b>Ubuntu 上的 Xray Reality + Mihomo + Clash 订阅 一站式部署工具</b>
</p>

<p align="center">
  <a href="https://github.com/l2208568163-sys/proxy-manager"><img src="https://img.shields.io/github/stars/l2208568163-sys/proxy-manager" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/l2208568163-sys/proxy-manager" alt="GitHub license"></a>
  <img src="https://img.shields.io/badge/version-3.4.0-blue" alt="Version">
</p>

<p align="center">
  🇨🇳 中文 | <a href="README_EN.md">🇺🇸 English</a>
</p>

---

## 📖 项目介绍

Proxy-Manager 是一个面向 Ubuntu Server 的代理节点自动化管理工具，把常见的节点部署与运维操作整合进一个交互式命令。

它可以帮你快速部署：

- **Xray Reality** 节点（VLESS + Reality + Vision）
- **Mihomo**（Clash Meta）客户端
- **Clash URL 订阅**（HTTP 订阅文件）
- **BBR** 网络优化

> 目标：用一条命令完成服务器代理环境的部署与日常管理。

---

## ✨ 功能特性

### 🔥 Xray Reality
- 协议：VLESS + Reality + Vision Flow + TCP
- 自动生成：`UUID`、`Private Key`、`Public Key`、`Short ID`
- 从 `443 / 8443 / 2053 / 2083` 中自动选择空闲端口
- **Web 认证跳过模式**：可选把节点端口放到网关默认放行的 `53 / 67 / 68 / 123`（DNS/DHCP/NTP），订阅自动加入 `fragment` 分片抗浅层 SNI/DPI，绕过咖啡厅/酒店等 captive portal（深度检测环境仍可能失效）
- 写配置前执行 Xray 配置校验，并生成 VLESS URI 与节点信息文件

### 🌐 Clash 订阅
- 兼容 Clash Verge、Clash Meta、Mihomo Party 等客户端
- 自动生成带**随机令牌**的订阅地址：`http://服务器IP/clash/<令牌>/config.yaml`，路径不可猜测，防止节点凭证被扫段获取
- 复制 URL 即可导入

### 🚀 Mihomo
- TUN 模式、Fake-IP DNS、自动路由、分流规则
- 先安装核心，再导入并校验订阅 URL 后才启动

### ⚡ 系统优化
- BBR、TCP Fast Open、FQ 队列
- Fail2ban 与 unattended-upgrades（安全加固模块）

---

## 📦 安装

### 系统要求
- **推荐**：Ubuntu 22.04+ / 24.04+
- **最低**：1 核 CPU / 512 MB 内存 / 10 GB 磁盘
- 需要 root 权限，且能访问 GitHub 等下载源

### 一键安装
```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh
```
安装器会：安装依赖 → 部署项目 → 创建 `proxy` 命令 → 创建订阅目录 `/var/www/html/clash`。

---

## 🎮 使用

启动管理菜单：
```bash
proxy
```

主菜单：
```
================================
 代理管理器 Proxy Manager v3.4.0
================================
 1. Xray Reality 节点
 2. Clash 订阅
 3. Mihomo 客户端
 4. 系统优化
 5. 安全加固
 6. Web 订阅服务
 7. 健康检查
 8. 查看节点信息
 9. 更新程序
10. 卸载 Proxy Manager
 0. 退出
```

命令行用法：
```bash
proxy             # 打开交互式菜单
proxy update      # 从 GitHub 快进更新并重启服务
proxy check       # 健康检查（服务/节点文件/配置）
proxy version     # 输出版本号
proxy --help      # 帮助
```

> **卸载**：`bash uninstall.sh`（普通卸载，保留 `data/`）或 `bash uninstall.sh --clean`（完全清理，含节点密钥）。

---

## 📱 Clash 导入
安装完成后会生成带随机令牌的订阅地址（形如 `http://服务器IP/clash/<令牌>/config.yaml`，可在主菜单 9 查看）：

以 Clash Verge 为例：
```
Profiles → New Profile → URL → 粘贴订阅地址
```

---

## 📂 项目结构
```
Proxy-Manager
├── README.md            🇨🇳 中文主页
├── README_EN.md         🇺🇸 English
├── LICENSE
├── VERSION
├── install.sh / uninstall.sh / update.sh
├── proxy-manager.sh     主菜单入口
├── lib/
│   └── common.sh        共享函数
├── modules/
│   ├── xray.sh          Xray Reality
│   ├── subscription.sh  Clash 订阅
│   ├── mihomo.sh        Mihomo 客户端
│   ├── system.sh        系统优化
│   ├── security.sh      安全加固
│   └── web.sh           Nginx 订阅服务
├── configs/             参考模板
├── docs/                文档
└── tests/
    └── check.sh         健康检查
```

---

## 🔐 安全说明
- **不要上传** `data/node.env`：含 `PRIVATE_KEY` / `UUID`。
- **订阅地址含随机令牌，等同节点凭证**，请勿公开分享；泄露后可重新生成订阅并更换 `SUB_TOKEN`。
- 本仓库 `.gitignore` 已默认忽略 `data/node.env`、`__pycache__/`。
- 使用 SSH 密钥登录，仅开放必要端口，定期更新系统 / Xray / Mihomo。
- 本项目不提供匿名性或绕过当地法律的保证；请遵守所在地法律与服务商规则。

---

## 🛠 Roadmap
- [x] **v3.1** Xray Reality / Mihomo / Clash 订阅 / DNS 优化
- [x] **v3.2** Web Dashboard / 服务状态 / 资源监控
- [x] **v3.2.1** 登录认证 / 服务重启与日志 / 订阅复制 / 节点二维码
- [x] **v3.2.2** Bug 修复：install.sh 补全 Python 依赖 / proxy 命令动态路径 / Clash 订阅 xudp / Reality dest 可配置
- [x] **v3.2.3** 引导层：install.sh 自动安装 Web 面板并打印访问信息 / webpanel.sh 增加启动·停止·地址·凭据·重置密码管理项 / 主菜单 Web 入口标星
- [x] **v3.2.8** 安全加固 + UI 重做：订阅随机令牌路径 / 移除默认口令兜底（web.env 缺失拒绝登录）/ 面板默认仅本机监听（公网需显式开启）/ 服务重启改 POST+确认 / 日志输出 HTML 转义 / 面板界面全新深色主题
- [x] **v3.2.9** 可靠性：`proxy update` 自动刷新面板依赖与 systemd 单元并重启 / install.sh 无条件刷新软件源索引 / mihomo 下载显式选版（标准构建优先、compatible 兜底）+ gzip 完整性校验 + 支持 GITHUB_TOKEN / nginx 独立站点配置（失败回滚、卸载恢复默认站点）/ 登录失败限速（防爆破）
- [x] **v3.3.0** Web 认证跳过（端口53 + 分片）/ **移除 Web 管理面板**（FastAPI 面板与 modules/webpanel.sh 已删除）/ 文档同步更新
- [x] **v3.4.0** **移除整个 DNS 模块**（AdGuard Home + 系统 DNS 优化，modules/dns.sh 已删除）/ 主菜单重排（移除 DNS 管理项）
- [ ] 多节点管理 / 流量统计 / API 管理

> 注：v3.3.0 起彻底移除 Web 管理面板（FastAPI + webpanel.sh）；**v3.4.0 起进一步移除整个 DNS 模块（含 AdGuard Home 与系统 DNS 优化，modules/dns.sh 已删除）**，主菜单相应重排。v3.2 系列中与面板相关的条目仅作为历史记录保留，当前版本不再包含该组件。

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
