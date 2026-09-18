# 代理管理器 Proxy Manager

![Linux](https://img.shields.io/badge/Linux-Ubuntu-orange)
![Xray](https://img.shields.io/badge/Xray-Reality-blue)
![Mihomo](https://img.shields.io/badge/Mihomo-Clash_Meta-green)

> 本文为中文版，完整英文文档见文末 **English** 折叠区（点击展开即切换到英文）。
> This page is in Chinese; the full English documentation is in the collapsible **English** section at the bottom (click to expand and switch to English).

当前版本 / Version：`3.2.0`

Proxy Manager 将常见的代理节点部署与维护操作整合为一个交互式命令。它可以部署 Xray VLESS Reality 节点、生成可由 Mihomo/Clash Meta 导入的订阅文件，并提供 Mihomo 客户端、DNS、网络优化、安全组件、健康检查、更新与卸载功能。

Proxy Manager turns common proxy-node deployment and maintenance tasks into a single interactive command. It can deploy Xray VLESS Reality nodes, generate subscription files importable by Mihomo/Clash Meta, and provides Mihomo client, DNS, network optimisation, security components, health checks, updates and uninstall.

## 功能概览 / Feature Overview

- 自动安装并配置 Xray VLESS Reality
  - 自动生成 UUID、Reality 密钥与 Short ID
  - 从 `443`、`8443`、`2053`、`2083` 中选择未占用端口
  - 写入配置前执行 Xray 配置校验
  - 生成 VLESS URI 和节点信息文件
- 生成 Mihomo/Clash Meta 订阅
  - 生成包含 `reality-opts.public-key` 与 `short-id` 的 `config.yaml`
  - 通过 `http://服务器IP/clash/config.yaml` 导入
  - 内置 Fake-IP DNS 基础配置
- Mihomo 客户端管理
  - 下载当前稳定版 Mihomo 核心
  - 导入并校验 HTTP/HTTPS 订阅
  - 可在已导入配置上启用 TUN 模式
- DNS 与网络优化
  - Cloudflare DNS 与 opportunistic DoT
  - 可选安装 AdGuard Home
  - BBR、FQ 与 TCP Fast Open
- 运维功能
  - Fail2ban 与 unattended-upgrades
  - 服务与配置健康检查
  - GitHub 快进更新
  - 带确认步骤的卸载
  - GitHub Actions ShellCheck 检查

## 运行环境 / Requirements

- Ubuntu 22.04 或更高版本
- root 权限或可用的 `sudo`
- 可访问 GitHub、Xray 与 Mihomo 的下载地址
- 建议至少 1 核 CPU、512 MB 内存

项目主要面向 Ubuntu；其他采用 `systemd` 和 `apt` 的 Debian 系统可能可用，但未作为正式支持目标。

The project targets Ubuntu primarily; other Debian-family systems using `systemd` and `apt` may work but are not formally supported.

## 安装 / Installation

以 root 身份执行 / Run as root:

```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh
```

如需在安装前同时更新系统软件包 / To also upgrade system packages before installing:

```bash
bash install.sh --update-system
```

安装器会 / The installer will:

1. 安装运行所需的软件包。 / Install required packages.
2. 将项目部署到 `/opt/proxy-manager`。 / Deploy the project to `/opt/proxy-manager`.
3. 创建 `proxy` 命令。 / Create the `proxy` command.
4. 创建订阅目录 `/var/www/html/clash`。 / Create the subscription directory `/var/www/html/clash`.

安装完成后打开管理菜单 / After install, open the menu:

```bash
proxy
```

> 安装器不会自动启用 UFW，也不会覆盖现有的 Nginx 站点配置。如果 UFW 已启用，相关模块只会添加所需端口规则；云服务器还需要在服务商安全组中放行相应端口。
> The installer does not enable UFW automatically and will not overwrite existing Nginx site config. If UFW is active, modules only add the needed port rules; cloud providers also require the ports opened in their security group.

## 快速开始 / Quick Start

### 1. 部署 Xray Reality

运行 `proxy` 后选择 `1. Xray Reality 节点`，再选择安装或重新配置。

脚本会生成节点参数，并保存到 / The script stores node parameters in:

```text
/opt/proxy-manager/data/node.env
```

文件权限为仅 root 可读。请妥善保护其中的 UUID、Reality 密钥和订阅地址。 / The file is root-readable only. Keep its UUID, Reality keys and subscription URL safe.

### 2. 发布订阅文件 / Publish the subscription

在主菜单中依次完成 / From the main menu:

1. 选择 `2. Clash 订阅`，生成或刷新 `config.yaml`。 / Pick `2. Clash subscription` to generate or refresh `config.yaml`.
2. 选择 `7. Web 订阅服务`，启用 Nginx 并发布文件。 / Pick `7. Web subscription service` to enable Nginx and publish the file.

默认订阅地址为 / Default subscription URL:

```text
http://服务器IP/clash/config.yaml
```

在 Mihomo Party、Clash Verge Rev 等支持 Mihomo 配置的客户端中添加该 URL 即可导入。

> 默认订阅使用 HTTP，适合受控环境或测试使用。若订阅会经由不可信网络传输，请使用自己的反向代理和 TLS 为其提供 HTTPS，并限制公开访问范围。
> The default subscription uses HTTP and suits controlled or test environments. If the subscription traverses untrusted networks, serve it over your own reverse proxy with TLS and restrict public access.

### 3. 查看节点信息 / View node info

主菜单选择 `9. 查看节点信息`，可以查看订阅地址与 VLESS URI。也可直接查看 / Or simply run:

```bash
sudo cat /opt/proxy-manager/data/node.env
```

## 主菜单 / Main Menu

| 选项 / Option | 功能 / Function |
| --- | --- |
| 1 | Xray Reality 的安装、重启、状态查看和移除 / Install, restart, status, remove Xray Reality |
| 2 | 生成或刷新 Mihomo/Clash Meta 订阅文件 / Generate or refresh Mihomo/Clash Meta subscription |
| 3 | 安装 Mihomo、导入订阅、启用 TUN 模式 / Install Mihomo, import subscription, enable TUN |
| 4 | 配置系统 DNS、安装 AdGuard Home、查看 DNS 状态 / Configure system DNS, install AdGuard Home, DNS status |
| 5 | 启用 BBR 与 TCP Fast Open / Enable BBR and TCP Fast Open |
| 6 | 安装和查看 Fail2ban、自动安全更新状态 / Install and view Fail2ban, auto security updates |
| 7 | 启用 Nginx 并发布订阅文件 / Enable Nginx and publish subscription |
| 8 | 运行健康检查 / Run health check |
| 9 | 查看节点 URI 与订阅地址 / View node URI and subscription URL |
| 10 | 从 GitHub 更新项目 / Update from GitHub |
| 11 | 卸载 Proxy Manager / Uninstall Proxy Manager |

## 命令行用法 / CLI Usage

```bash
proxy             # 打开交互式菜单 / open interactive menu
proxy update      # 从 GitHub 拉取 main 分支并重启正在运行的服务 / fast-forward pull and restart services
proxy check       # 检查服务、节点文件与可用配置 / check services, node file and config
proxy version     # 输出版本号 / print version
proxy --help      # 查看简要帮助 / short help
```

## Mihomo 客户端与 TUN 模式 / Mihomo Client & TUN

Mihomo 模块是一个独立客户端管理工具：先安装核心，再输入一个 HTTP 或 HTTPS 订阅 URL，脚本验证配置后才会启动服务。

启用 TUN 会修改主机路由和 DNS 劫持规则。它适合需要让该机器通过 Mihomo 出网的客户端场景。不要在同一台承载 Xray 节点的服务器上随意启用 TUN；如果不了解路由回环和服务出口的影响，请在独立客户端或测试机上使用。

生成的订阅包含 Reality 所需的 `public-key` 与 `short-id` 字段，字段格式参考 [Mihomo VLESS 文档](https://wiki.metacubex.one/en/config/proxies/vless/)。TUN 行为以 [Mihomo TUN 文档](https://wiki.metacubex.one/en/config/inbound/tun/) 为准。

The Mihomo module is a standalone client tool: install the core, then enter an HTTP/HTTPS subscription URL; the script validates the config before starting the service. Enabling TUN modifies host routing and DNS hijacking rules. Do not casually enable TUN on the same server that hosts the Xray node; use a separate client or test machine if you are unsure about routing loops and service egress.

## DNS

DNS 模块包含两种互不冲突的选择 / The DNS module offers two non-conflicting options:

- **系统 DNS**：向 `systemd-resolved` 写入 Cloudflare DNS 和 opportunistic DoT 配置。 / **System DNS**: writes Cloudflare DNS and opportunistic DoT into `systemd-resolved`.
- **AdGuard Home**：从官方发布页下载并安装服务；首次安装后在 `http://服务器IP:3000` 完成其初始化。需要放行 `3000/TCP` 进行设置，以及按实际用途放行 DNS 端口。 / **AdGuard Home**: installed from the official release page; finish setup at `http://服务器IP:3000`. Open `3000/TCP` for setup and the DNS ports as needed.

安装 AdGuard Home 前请确认端口 53、80 和 3000 没有被现有服务占用。 / Before installing AdGuard Home, ensure ports 53, 80 and 3000 are free.

## 端口与防火墙 / Ports & Firewall

| 服务 / Service | 端口 / Port | 用途 / Purpose |
| --- | --- | --- |
| Xray Reality | 自动选择：443 / 8443 / 2053 / 2083 | VLESS Reality 入站 / VLESS Reality inbound |
| Nginx | 80/TCP | 订阅文件 / Subscription file |
| AdGuard Home | 3000/TCP | 首次 Web 设置 / First-time web setup |
| AdGuard Home | 53/UDP、53/TCP | DNS 服务（如启用）/ DNS service (if enabled) |

除服务器防火墙外，还要在云服务商的安全组或网络防火墙中配置对应端口。 / Besides the server firewall, open the ports in the cloud provider's security group or network firewall.

## 配置与数据位置 / Config & Data Locations

| 路径 / Path | 说明 / Description |
| --- | --- |
| `/opt/proxy-manager` | 已安装的项目代码 / Installed project code |
| `/opt/proxy-manager/data/node.env` | 节点数据，仅 root 可读 / Node data, root-readable only |
| `/usr/local/etc/xray/config.json` | Xray 配置 / Xray config |
| `/var/www/html/clash/config.yaml` | 可公开导入的 Mihomo 订阅 / Publicly importable Mihomo subscription |
| `/etc/mihomo/config.yaml` | Mihomo 客户端导入的配置 / Mihomo client config |
| `/etc/systemd/system/mihomo.service` | Mihomo systemd 服务 / Mihomo systemd service |
| `/etc/sysctl.d/99-proxy-manager.conf` | BBR 与 TCP Fast Open 配置 / BBR and TCP Fast Open config |
| `/etc/systemd/resolved.conf.d/proxy-manager.conf` | 系统 DNS 覆盖配置 / System DNS override config |

仓库中的 `configs/` 目录包含可供参考的 Xray 与 Mihomo 模板。不要将真实私钥、服务器密码或私有订阅提交到 GitHub。 / The `configs/` directory holds reference Xray and Mihomo templates. Never commit real private keys, server passwords or private subscriptions to GitHub.

## 健康检查与排障 / Health Check & Troubleshooting

先运行 / First run:

```bash
sudo proxy check
```

常用检查命令 / Common checks:

```bash
sudo systemctl status xray
sudo systemctl status mihomo
sudo systemctl status nginx
sudo journalctl -u xray -n 100 --no-pager
sudo journalctl -u mihomo -n 100 --no-pager
```

### 订阅地址无法访问 / Subscription unreachable

1. 确认已完成 Xray 部署，并生成过订阅文件。 / Xray deployed and a subscription generated.
2. 在菜单中启用 Web subscription service。 / Enable Web subscription service in the menu.
3. 检查 Nginx 是否运行：`systemctl status nginx`。 / Check Nginx: `systemctl status nginx`.
4. 检查服务器防火墙和云安全组是否放行 `80/TCP`。 / Verify firewall and security group allow `80/TCP`.
5. 检查 `/var/www/html/clash/config.yaml` 是否存在。 / Check `/var/www/html/clash/config.yaml` exists.

### Xray 无法启动 / Xray won't start

1. 查看 `systemctl status xray` 和日志。 / Check `systemctl status xray` and logs.
2. 确认所选端口没有被其他服务占用。 / Port not taken by another service.
3. 在 Xray 菜单中重新生成配置；脚本会先运行配置校验。 / Regenerate config in the Xray menu; the script validates first.

### Mihomo 无法启动 / Mihomo won't start

1. 确认导入的订阅 URL 可访问。 / Imported subscription URL is reachable.
2. 使用 `proxy check` 验证本地 Mihomo 配置。 / Use `proxy check` to validate the local Mihomo config.
3. 若启用了 TUN，检查主机路由、DNS 和其他 VPN/代理程序是否冲突。 / If TUN is enabled, check host routing, DNS and other VPN/proxy conflicts.

## 更新 / Update

安装目录是 Git 仓库时，可执行 / When the install dir is a Git repo:

```bash
sudo proxy update
```

更新采用 fast-forward 方式，不会自动合并本地冲突。如果你直接修改了 `/opt/proxy-manager` 中的文件，请先提交、暂存或还原这些改动后再更新。 / Updates use fast-forward and will not auto-merge local conflicts. Commit, stash or revert any edited files under `/opt/proxy-manager` before updating.

## 卸载 / Uninstall

在主菜单中选择 `11. 卸载 Proxy Manager`。脚本会分别确认 / Choose `11. Uninstall` from the main menu. The script confirms separately:

1. 是否移除 Proxy Manager 命令和 Mihomo 服务。 / Remove the Proxy Manager command and Mihomo service.
2. 是否删除节点数据和订阅文件。 / Delete node data and subscription files.
3. 是否删除项目目录。 / Delete the project directory.

默认不会自动移除 Xray；如需移除 Xray，请先在 Xray 子菜单中执行移除操作。 / Xray is not removed automatically; remove it from the Xray submenu first if desired.

## 安全说明 / Security Notes

- 使用 SSH 密钥登录，避免公开 root 密码。 / Use SSH keys, avoid exposing the root password.
- 为服务器和云账号启用多因素认证。 / Enable MFA for server and cloud accounts.
- 仅开放实际需要的端口。 / Open only the ports you actually need.
- 定期更新系统、Xray、Mihomo 和 AdGuard Home。 / Keep system, Xray, Mihomo and AdGuard Home updated.
- 不要将 `node.env`、私钥或含凭据的订阅链接分享给不可信对象。 / Never share `node.env`, private keys or credentialed subscription links.
- 本项目不提供流量匿名性或绕过当地法律的保证；请遵守所在地法律、服务商规则和网络使用政策。 / This project gives no guarantee of anonymity or circumvention of local laws; comply with applicable laws and provider rules.

## 开发与质量检查 / Development & Quality Checks

GitHub Actions 会在推送和拉取请求时运行 ShellCheck。提交前也可在 Ubuntu 上运行 / GitHub Actions runs ShellCheck on push and PR. Locally on Ubuntu:

```bash
shellcheck install.sh update.sh uninstall.sh proxy-manager.sh lib/common.sh modules/*.sh tests/check.sh
```

欢迎通过 Issue 或 Pull Request 报告问题、提出功能建议或改进文档。 / Issues and Pull Requests for bugs, suggestions or doc fixes are welcome.

---

<details>
<summary>🇬🇧 English Documentation (click to expand / 点击展开)</summary>

# Proxy Manager

> Ubuntu 上的 Xray Reality 节点、Mihomo 客户端和订阅文件管理工具。

当前版本：`3.2.0`

Proxy Manager 将常见的代理节点部署和维护操作整理为一个交互式命令。它可以部署 Xray VLESS Reality 节点、生成可由 Mihomo/Clash Meta 导入的订阅文件，并提供 Mihomo 客户端、DNS、网络优化、安全组件、健康检查、更新和卸载功能。

## 功能概览

- 自动安装并配置 Xray VLESS Reality
  - 自动生成 UUID、Reality 密钥与 Short ID
  - 从 `443`、`8443`、`2053`、`2083` 中选择未占用端口
  - 写入配置前执行 Xray 配置校验
  - 生成 VLESS URI 和节点信息文件
- 生成 Mihomo/Clash Meta 订阅
  - 生成包含 `reality-opts.public-key` 和 `short-id` 的 `config.yaml`
  - 通过 `http://服务器IP/clash/config.yaml` 导入
  - 内置 Fake-IP DNS 基础配置
- Mihomo 客户端管理
  - 下载当前稳定版 Mihomo 核心
  - 导入并校验 HTTP/HTTPS 订阅
  - 可在已导入配置上启用 TUN 模式
- DNS 与网络优化
  - Cloudflare DNS 与 opportunistic DoT
  - 可选安装 AdGuard Home
  - BBR、FQ 与 TCP Fast Open
- 运维功能
  - Fail2ban 与 unattended-upgrades
  - 服务与配置健康检查
  - GitHub 快进更新
  - 带确认步骤的卸载
  - GitHub Actions ShellCheck 检查

## 运行环境

- Ubuntu 22.04 或更高版本
- root 权限或可用的 `sudo`
- 可访问 GitHub、Xray 与 Mihomo 的下载地址
- 建议至少 1 核 CPU、512 MB 内存

项目主要面向 Ubuntu；其他采用 `systemd` 和 `apt` 的 Debian 系统可能可用，但未作为正式支持目标。

## 安装

以 root 身份执行：

```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh
```

如需在安装前同时更新系统软件包：

```bash
bash install.sh --update-system
```

安装器会：

1. 安装运行所需的软件包。
2. 将项目部署到 `/opt/proxy-manager`。
3. 创建 `proxy` 命令。
4. 创建订阅目录 `/var/www/html/clash`。

安装完成后打开管理菜单：

```bash
proxy
```

> 安装器不会自动启用 UFW，也不会覆盖现有的 Nginx 站点配置。如果 UFW 已启用，相关模块只会添加所需端口规则；云服务器还需要在服务商安全组中放行相应端口。

## 快速开始

### 1. 部署 Xray Reality

运行 `proxy` 后选择 `1. Xray Reality`，再选择安装或重新配置。

脚本会生成节点参数，并保存到：

```text
/opt/proxy-manager/data/node.env
```

文件权限为仅 root 可读。请妥善保护其中的 UUID、Reality 密钥和订阅地址。

### 2. 发布订阅文件

在主菜单中依次完成：

1. 选择 `2. Clash subscription`，生成或刷新 `config.yaml`。
2. 选择 `7. Web subscription service`，启用 Nginx 并发布文件。

默认订阅地址为：

```text
http://服务器IP/clash/config.yaml
```

在 Mihomo Party、Clash Verge Rev 等支持 Mihomo 配置的客户端中添加该 URL 即可导入。

> 默认订阅使用 HTTP，适合受控环境或测试使用。若订阅会经由不可信网络传输，请使用自己的反向代理和 TLS 为其提供 HTTPS，并限制公开访问范围。

### 3. 查看节点信息

主菜单选择 `9. View node`，可以查看订阅地址与 VLESS URI。也可直接查看：

```bash
sudo cat /opt/proxy-manager/data/node.env
```

## 主菜单

| 选项 | 功能 |
| --- | --- |
| 1 | Xray Reality 的安装、重启、状态查看和移除 |
| 2 | 生成或刷新 Mihomo/Clash Meta 订阅文件 |
| 3 | 安装 Mihomo、导入订阅、启用 TUN 模式 |
| 4 | 配置系统 DNS、安装 AdGuard Home、查看 DNS 状态 |
| 5 | 启用 BBR 与 TCP Fast Open |
| 6 | 安装和查看 Fail2ban、自动安全更新状态 |
| 7 | 启用 Nginx 并发布订阅文件 |
| 8 | 运行健康检查 |
| 9 | 查看节点 URI 与订阅地址 |
| 10 | 从 GitHub 更新项目 |
| 11 | 卸载 Proxy Manager |

## 命令行用法

```bash
proxy             # 打开交互式菜单
proxy update      # 从 GitHub 拉取 main 分支并重启正在运行的服务
proxy check       # 检查服务、节点文件与可用配置
proxy version     # 输出版本号
proxy --help      # 查看简要帮助
```

## Mihomo 客户端与 TUN 模式

Mihomo 模块是一个独立客户端管理工具：先安装核心，再输入一个 HTTP 或 HTTPS 订阅 URL，脚本验证配置后才会启动服务。

启用 TUN 会修改主机路由和 DNS 劫持规则。它适合需要让该机器通过 Mihomo 出网的客户端场景。不要在同一台承载 Xray 节点的服务器上随意启用 TUN；如果不了解路由回环和服务出口的影响，请在独立客户端或测试机上使用。

生成的订阅包含 Reality 所需的 `public-key` 与 `short-id` 字段，字段格式参考 [Mihomo VLESS 文档](https://wiki.metacubex.one/en/config/proxies/vless/)。TUN 行为以 [Mihomo TUN 文档](https://wiki.metacubex.one/en/config/inbound/tun/) 为准。

## DNS

DNS 模块包含两种互不冲突的选择：

- **系统 DNS**：向 `systemd-resolved` 写入 Cloudflare DNS 和 opportunistic DoT 配置。
- **AdGuard Home**：从官方发布页下载并安装服务；首次安装后在 `http://服务器IP:3000` 完成其初始化。需要放行 `3000/TCP` 进行设置，以及按实际用途放行 DNS 端口。

安装 AdGuard Home 前请确认端口 53、80 和 3000 没有被现有服务占用。

## 端口与防火墙

| 服务 | 端口 | 用途 |
| --- | --- |
| Xray Reality | 自动选择：443 / 8443 / 2053 / 2083 | VLESS Reality 入站 |
| Nginx | 80/TCP | 订阅文件 |
| AdGuard Home | 3000/TCP | 首次 Web 设置 |
| AdGuard Home | 53/UDP、53/TCP | DNS 服务（如启用） |

除服务器防火墙外，还要在云服务商的安全组或网络防火墙中配置对应端口。

## 配置与数据位置

| 路径 | 说明 |
| --- | --- |
| `/opt/proxy-manager` | 已安装的项目代码 |
| `/opt/proxy-manager/data/node.env` | 节点数据，仅 root 可读 |
| `/usr/local/etc/xray/config.json` | Xray 配置 |
| `/var/www/html/clash/config.yaml` | 可公开导入的 Mihomo 订阅 |
| `/etc/mihomo/config.yaml` | Mihomo 客户端导入的配置 |
| `/etc/systemd/system/mihomo.service` | Mihomo systemd 服务 |
| `/etc/sysctl.d/99-proxy-manager.conf` | BBR 与 TCP Fast Open 配置 |
| `/etc/systemd/resolved.conf.d/proxy-manager.conf` | 系统 DNS 覆盖配置 |

仓库中的 `configs/` 目录包含可供参考的 Xray 与 Mihomo 模板。不要将真实私钥、服务器密码或私有订阅提交到 GitHub。

## 健康检查与排障

先运行：

```bash
sudo proxy check
```

常用检查命令：

```bash
sudo systemctl status xray
sudo systemctl status mihomo
sudo systemctl status nginx
sudo journalctl -u xray -n 100 --no-pager
sudo journalctl -u mihomo -n 100 --no-pager
```

### 订阅地址无法访问

1. 确认已完成 Xray 部署，并生成过订阅文件。
2. 在菜单中启用 Web subscription service。
3. 检查 Nginx 是否运行：`systemctl status nginx`。
4. 检查服务器防火墙和云安全组是否放行 `80/TCP`。
5. 检查 `/var/www/html/clash/config.yaml` 是否存在。

### Xray 无法启动

1. 查看 `systemctl status xray` 和日志。
2. 确认所选端口没有被其他服务占用。
3. 在 Xray 菜单中重新生成配置；脚本会先运行配置校验。

### Mihomo 无法启动

1. 确认导入的订阅 URL 可访问。
2. 使用 `proxy check` 验证本地 Mihomo 配置。
3. 若启用了 TUN，检查主机路由、DNS 和其他 VPN/代理程序是否冲突。

## 更新

安装目录是 Git 仓库时，可执行：

```bash
sudo proxy update
```

更新采用 fast-forward 方式，不会自动合并本地冲突。如果你直接修改了 `/opt/proxy-manager` 中的文件，请先提交、暂存或还原这些改动后再更新。

## 卸载

在主菜单中选择 `11. Uninstall`。脚本会分别确认：

1. 是否移除 Proxy Manager 命令和 Mihomo 服务。
2. 是否删除节点数据和订阅文件。
3. 是否删除项目目录。

默认不会自动移除 Xray；如需移除 Xray，请先在 Xray 子菜单中执行移除操作。

## 安全说明

- 使用 SSH 密钥登录，避免公开 root 密码。
- 为服务器和云账号启用多因素认证。
- 仅开放实际需要的端口。
- 定期更新系统、Xray、Mihomo 和 AdGuard Home。
- 不要将 `node.env`、私钥或含凭据的订阅链接分享给不可信对象。
- 本项目不提供流量匿名性或绕过当地法律的保证；请遵守所在地法律、服务商规则和网络使用政策。

## 开发与质量检查

GitHub Actions 会在推送和拉取请求时运行 ShellCheck。提交前也可在 Ubuntu 上运行：

```bash
shellcheck install.sh update.sh uninstall.sh proxy-manager.sh lib/common.sh modules/*.sh tests/check.sh
```

欢迎通过 Issue 或 Pull Request 报告问题、提出功能建议或改进文档。

</details>
