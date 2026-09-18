# 🚀 Proxy-Manager

<p align="center">
  <b>Ubuntu 上的 Xray Reality + Mihomo + Clash 订阅 + Web 管理面板 一站式部署工具</b>
</p>

<p align="center">
  <a href="https://github.com/l2208568163-sys/proxy-manager"><img src="https://img.shields.io/github/stars/l2208568163-sys/proxy-manager" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/l2208568163-sys/proxy-manager" alt="GitHub license"></a>
  <img src="https://img.shields.io/badge/version-3.2.3-blue" alt="Version">
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
- **AdGuard Home** DNS
- **BBR** 网络优化
- **Web 管理面板**（v3.2 起，带登录认证）

> 目标：用一条命令完成服务器代理环境的部署与日常管理。

---

## ✨ 功能特性

### 🔥 Xray Reality
- 协议：VLESS + Reality + Vision Flow + TCP
- 自动生成：`UUID`、`Private Key`、`Public Key`、`Short ID`
- 从 `443 / 8443 / 2053 / 2083` 中自动选择空闲端口
- 写配置前执行 Xray 配置校验，并生成 VLESS URI 与节点信息文件

### 🌐 Clash 订阅
- 兼容 Clash Verge、Clash Meta、Mihomo Party 等客户端
- 自动生成：`http://服务器IP/clash/config.yaml`
- 复制 URL 即可导入

### 🚀 Mihomo
- TUN 模式、Fake-IP DNS、自动路由、分流规则
- 先安装核心，再导入并校验订阅 URL 后才启动

### 🛡 DNS 优化
- 系统 DNS（Cloudflare + opportunistic DoT）
- 可选安装 AdGuard Home（DoH / DNS 缓存）

### ⚡ 系统优化
- BBR、TCP Fast Open、FQ 队列
- Fail2ban 与 unattended-upgrades（安全加固模块）

### 🖥 Web 管理面板（v3.2 / v3.2.1）
- 服务状态、CPU、内存、网络监控
- **登录认证**（随机会话令牌，凭据存于 `data/web.env`）
- 在线重启服务、查看 Xray/Mihomo 日志
- Clash 订阅一键复制、节点二维码（扫码导入）

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
 代理管理器 Proxy Manager v3.2.1
================================
 1. Xray Reality 节点
 2. Clash 订阅
 3. Mihomo 客户端
 4. DNS 管理
 5. 系统优化
 6. 安全加固
 7. Web 订阅服务
 8. 健康检查
 9. 查看节点信息
10. 更新程序
11. 卸载 Proxy Manager
12. Web 管理面板
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
安装完成后会生成：`http://服务器IP/clash/config.yaml`

以 Clash Verge 为例：
```
Profiles → New Profile → URL → 粘贴订阅地址
```

---

## 🖥 Web 管理面板
访问：`http://服务器IP:8080`（首次安装由 `主菜单 → 12. Web 管理面板 → 1` 生成随机密码并打印）

功能：服务状态、资源监控、在线重启、日志查看、订阅复制、节点二维码。

> ⚠ 即便有登录认证，公网裸奔 8080 仍有风险；建议用 SSH 隧道（`ssh -L 8080:127.0.0.1:8080 用户@IP` 后访问 `localhost:8080`）或前置带 TLS 的反向代理。

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
│   ├── dns.sh           DNS / AdGuard Home
│   ├── system.sh        系统优化
│   ├── security.sh      安全加固
│   ├── web.sh           Nginx 订阅服务
│   └── webpanel.sh      Web 管理面板部署
├── configs/             参考模板
├── docs/                文档
├── tests/
│   └── check.sh         健康检查
└── web/                 FastAPI 面板
    ├── app.py / auth.py / service.py / qrgen.py
    ├── requirements.txt
    ├── templates/        index.html / login.html
    └── static/           style.css
```

---

## 🔐 安全说明
- **不要上传** `data/node.env` 和 `data/web.env`：前者含 `PRIVATE_KEY` / `UUID`，后者含后台密码。
- 本仓库 `.gitignore` 已默认忽略 `data/web.env`、`data/node.env`、`web/venv/`、`__pycache__/`。
- 使用 SSH 密钥登录，仅开放必要端口，定期更新系统 / Xray / Mihomo / AdGuard Home。
- 本项目不提供匿名性或绕过当地法律的保证；请遵守所在地法律与服务商规则。

---

## 🛠 Roadmap
- [x] **v3.1** Xray Reality / Mihomo / Clash 订阅 / DNS 优化
- [x] **v3.2** Web Dashboard / 服务状态 / 资源监控
- [x] **v3.2.1** 登录认证 / 服务重启与日志 / 订阅复制 / 节点二维码
- [x] **v3.2.2** Bug 修复：install.sh 补全 Python 依赖 / proxy 命令动态路径 / Clash 订阅 xudp / Reality dest 可配置
- [x] **v3.2.3** 引导层：install.sh 自动安装 Web 面板并打印访问信息 / webpanel.sh 增加启动·停止·地址·凭据·重置密码管理项 / 主菜单 Web 入口标星
- [ ] **v3.3** 多节点管理 / 流量统计 / API 管理

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
