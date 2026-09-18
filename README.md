# Proxy Manager

![Linux](https://img.shields.io/badge/Linux-Ubuntu-orange)
![Xray](https://img.shields.io/badge/Xray-Reality-blue)
![Mihomo](https://img.shields.io/badge/Mihomo-Clash_Meta-green)
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
| --- | --- | --- |
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

## 项目结构

```text
proxy-manager
├── install.sh                  # 安装器
├── proxy-manager.sh            # 主菜单与 proxy 命令入口
├── update.sh                   # GitHub 更新
├── uninstall.sh                # 带确认的卸载器
├── VERSION
├── lib/
│   └── common.sh               # 模块共享函数
├── modules/
│   ├── xray.sh
│   ├── subscription.sh
│   ├── mihomo.sh
│   ├── dns.sh
│   ├── system.sh
│   ├── security.sh
│   └── web.sh
├── configs/                    # 配置模板
├── docs/                       # 安装、架构与排障文档
├── tests/check.sh              # 健康检查
└── .github/workflows/
    └── shellcheck.yml          # ShellCheck 工作流
```

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
