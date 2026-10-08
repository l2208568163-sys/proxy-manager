# 🚀 Proxy-Manager

<p align="center">
  <b>Ubuntu 上的 Xray Reality + Clash 订阅 一站式部署工具</b>
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
- **Clash URL 订阅**（HTTP 订阅文件）
- **BBR** 网络优化
> 客户端内核（Clash Verge / v2rayN 等）装在你自己的设备上即可，本项目不再内置客户端模块。

> 目标：用一条命令完成服务器代理环境的部署与日常管理。

---

## ✨ 功能特性

### 🔥 Xray Reality
- 协议：VLESS + Reality + Vision Flow + TCP
- 自动生成：`UUID`、`Private Key`、`Public Key`、`Short ID`
- 从 `443 / 8443 / 2053 / 2083` 中自动选择空闲端口
- **WiFi web 跳验证模式**：可开一个**独立的专属节点**（Vmess + mKCP，UDP），端口落在网关默认放行的 `53 / 67 / 68 / 123` 并**伪装成 DNS**，绕过咖啡厅/酒店等 captive portal（详见下方专节；深度检测环境仍可能失效）
- 写配置前执行 Xray 配置校验，并生成 VLESS URI 与节点信息文件

### 🌐 Clash 订阅
- 兼容 Clash Verge、Clash Meta、Mihomo Party 等客户端
- 自动生成带**随机令牌**的订阅地址：`http://服务器IP/clash/<令牌>/config.yaml`，路径不可猜测，防止节点凭证被扫段获取
- 复制 URL 即可导入

### 📶 WiFi web 跳验证（独立专属节点 · Vmess + mKCP）
- **独立节点**：独立 Xray inbound（Vmess + mKCP，**UDP**），与主节点并存 —— 各自端口、各自 UUID，互不影响
- 端口落在网关默认放行的 `53 / 67 / 68 / 123`，并把流量**伪装成 DNS**。热点为跳转 Web 认证页会放行 UDP 53 的 DNS 报文，故走 UDP 最有效（Reality 只能跑 TCP，过不去）
- 优先使用 **53**；若被 systemd-resolved 的 stub 监听占用，可自动释放（关闭 stub 并改用静态 DNS，**保留机器原有 DNS**，原 `/etc/resolv.conf` 备份为 `.bak.proxy-manager`）；释放后若 DNS 不可用会**自动回滚**
- 参数对齐 3x-ui 默认：MTU 1350 / TTI 50 / 上下行 20 MB/s / congestion 关 / read·write buffer 2
- **DNS 伪装域名固定 `www.baidu.com`（两端必须一致）**：DNS 头长度随域名变化，两端不同则每包错位。v2rayN/v2rayNG 对 `type=dns` 链接**不把 host 传给掩码**，客户端实际用核心默认 `www.baidu.com`，服务端因此默认跟随；节点配置里的 `WIFI_DOMAIN` 可自定义，但必须与客户端一致
- **核心版本兼容（重要）**：Xray **v26.2.6 起**移除了 `kcpSettings.header/seed`，DNS 伪装改由 `finalmask` 的 UDP 掩码实现。且旧版 `header:dns` 的线上格式是「DNS 头 + XOR 混淆」**双层叠加**，两代核心的掩码类型名也不同（v26.2~26.3 用 `header-dns`+`mkcp-original`，v26.7+ 用 `mkcp-legacy`）。脚本写入配置时自动适配：先用 `mkcp-legacy` 试校验，核心不识别就换 `header-dns` 双层组合重试（已用 26.3.27 服务端 + 26.9.9 客户端真实互联验证）
- 客户端：用 **v2rayN / v2rayNG（Xray 核心）** 导入输出的 `vmess://` 链接，开启“DNS 代理 / 防泄漏”走全局。clash / sing-box 对 UDP:53 伪装支持不佳，故该节点**不进 Clash 订阅**
- 已知限制：阿里云等部分厂商已封禁 53 端口个人使用；深度检测（SNI 阻断 / 真实 DNS 代理）环境仍可能失效

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

### 覆盖安装时的备份与恢复
- 若 `/opt/proxy-manager` 已存在，安装器会先把 `data/` 备份到 `/opt/proxy-manager-backup-<时间戳>`
- 随后列出**本次及历史遗留的**全部备份，由你决定是否恢复（输入编号，或 `0` = 不恢复、用全新配置）
- 非交互场景（如 `curl ... | bash install.sh` 无终端）会自动恢复**最新**备份，保证节点不丢
- 可用参数直接跳过询问：`--restore`（直接恢复最新）、`--no-restore`（不恢复，备份目录保留）

> 恢复会用备份文件覆盖 `data/` 下的同名文件（节点密钥会被替换），请看清编号再回车。

---

## 🎮 使用

启动管理菜单：
```bash
proxy
```

主菜单：
```
================================
 代理管理器 Proxy Manager v3.4.4
================================
 1. Xray Reality 节点
 2. Clash 订阅
 3. 系统优化
 4. 安全加固
 5. Web 订阅服务
 6. 健康检查
 7. 查看节点信息
 8. 更新程序
 9. 卸载 Proxy Manager
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

### 卸载时的备份处理
卸载收尾会列出 `/opt/proxy-manager-backup-*` 下的历史备份，由你选择：
- `a` = 全部删除　`n` = 全部保留（**默认**）　`s` = 按编号选择删除（如输入 `1 3`）

备份里含节点密钥 `data/`，**删除后不可恢复**；保留的备份会在下次 `install.sh` 时再次被问到是否恢复。

---

## 📱 Clash 导入
安装完成后会生成带随机令牌的订阅地址（形如 `http://服务器IP/clash/<令牌>/config.yaml`，可在主菜单 7 查看）：

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
- 使用 SSH 密钥登录，仅开放必要端口，定期更新系统 / Xray。
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
- [x] **v3.4.4** **新增 TCP53 对照测试节点**（Xray 菜单 8/9）：VLESS 裸协议 + TCP:53，与 WiFi 节点的 UDP:53 并存。配合 443/53TCP/53UDP 三个入口分别测速，即可判断中间网络放行的是 TCP 53、UDP 53、还是劫持/都不放——不再盲改配置
- [x] **v3.4.3** **修复 WiFi 节点在新版 Xray 上无法启动 / 连不通**：v26.2.6+ 移除了 `kcpSettings.header/seed`，DNS 伪装迁移到 `finalmask` UDP 掩码；旧格式实为「DNS 头 + XOR」双层，且 v26.2~26.3（`header-dns`+`mkcp-original`）与 v26.7+（`mkcp-legacy`）类型名互不兼容，写入配置时自动试错适配（已用 26.3.27 服务端 + 26.9.9 客户端真实互联验证 HTTP 200）
- [x] **v3.4.2** **修复「选完功能整个程序退出」**：主菜单以 `|| module_failed` 包裹各模块，模块出错不再连带退出、错误信息暂停展示；Xray 菜单 1/6/7、load_node_data、write_xray_config、restart_xray_and_wait 全面改为「可读错误 + 优雅返回」，不再依赖 set -e 兜底
- [x] **v3.4.1** **备份可交互管理**：安装时列出本次+历史备份由用户选择是否恢复（新增 `--restore` / `--no-restore`，非交互自动恢复最新）/ 卸载收尾询问历史备份「全部删除 / 全部保留 / 按编号删除」；WiFi 跳验证改用 Vmess + mKCP（UDP + DNS 伪装）
- [x] **v3.4.0** **移除整个 DNS 模块**（AdGuard Home + 系统 DNS 优化，modules/dns.sh 已删除）/ **移除 Mihomo 客户端模块**（modules/mihomo.sh 已删除）/ **“Web 认证跳过”更名为「WiFi web 跳验证」并改为独立专属节点**（独立 inbound、独立密钥与端口，不覆盖主节点；可自动释放 53）/ 主菜单重排
- [ ] 多节点管理 / 流量统计 / API 管理

> 注：v3.3.0 起彻底移除 Web 管理面板（FastAPI + webpanel.sh）；**v3.4.0 起进一步移除整个 DNS 模块（含 AdGuard Home 与系统 DNS 优化，modules/dns.sh 已删除）**，主菜单相应重排。v3.2 系列中与面板相关的条目仅作为历史记录保留，当前版本不再包含该组件。

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
