# Proxy Manager

Proxy Manager is an Ubuntu-focused command-line manager for an Xray VLESS Reality node, a Mihomo client, and a shareable Mihomo subscription.

## Features

- Xray Reality installation with automatic port selection and validated configuration
- A Mihomo-compatible `config.yaml` subscription at `/clash/config.yaml`
- Separate Mihomo client installation and validated subscription import
- DNS, BBR/TCP Fast Open, Fail2ban, update, uninstall, and health-check commands
- ShellCheck workflow for every push and pull request

## Quick start

```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
sudo bash install.sh
sudo proxy
```

See [installation notes](docs/install.md), [architecture](docs/architecture.md), and [troubleshooting](docs/troubleshooting.md).

## Commands

```bash
proxy             # interactive menu
proxy update      # fast-forward update from GitHub
proxy check       # validate service and configuration state
proxy version     # print version
```

The project does not automatically enable a firewall or overwrite an existing Nginx site configuration.
