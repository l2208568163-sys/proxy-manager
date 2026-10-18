# 🚀 Proxy-Manager

<p align="center">
  <b>One-click deployment tool for Xray Reality + Clash subscription + Web dashboard on Ubuntu Server</b>
</p>

<p align="center">
  <a href="https://github.com/l2208568163-sys/proxy-manager"><img src="https://img.shields.io/github/stars/l2208568163-sys/proxy-manager" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/l2208568163-sys/proxy-manager" alt="GitHub license"></a>
  <img src="https://img.shields.io/badge/version-3.3.0-blue" alt="Version">
</p>

<p align="center">
  🇺🇸 English | <a href="README.md">🇨🇳 中文</a>
</p>

---

## 📖 Introduction

Proxy-Manager is an automated proxy-node management tool for Ubuntu Server. It turns common deployment and maintenance tasks into a single interactive command.

It helps you deploy:

- **Xray Reality** nodes (VLESS + Reality + Vision)
- **Clash URL subscription** (random-token path, auto-published via nginx)
- **BBR** network optimization (enabled during install)
- **Web management dashboard** (with login auth)

> Goal: deploy and manage a server proxy environment with one command.
> Since v3.3.0 the project focuses on its core: the Mihomo client and DNS
> management modules were removed, and system optimization / security hardening
> moved into the installer. See the Roadmap.

---

## ✨ Features

### 🔥 Xray Reality
- Protocols: VLESS + Reality + Vision Flow + TCP
- Auto-generates: `UUID`, `Private Key`, `Public Key`, `Short ID`
- Picks a free port from `443 / 8443 / 2053 / 2083`
- Validates the Xray config before writing, and generates a VLESS URI + node info file

### 🌐 Clash Subscription & Publishing
- Compatible with Clash Verge, Clash Meta, Mihomo Party, etc.
- Auto-generates a subscription URL with a **random token**: `http://SERVER_IP/clash/<token>/config.yaml` — the path is unguessable, keeping node credentials safe from scanners
- After generation the nginx site is configured and published automatically (idempotent, auto-rollback on failure)
- Paste the URL to import

### ⚡ System-level optimization (during install)
- BBR, TCP Fast Open, FQ queue (enabled by default)
- Optional `--harden`: Fail2ban and unattended-upgrades

### 🖥 Web Dashboard (v3.2 / v3.2.1)
- Service status, CPU, memory, network monitoring
- **Login auth** (random session token; credentials in `data/web.env`)
- Restart services and view Xray/Nginx logs online
- One-click copy of the Clash subscription, node QR code

---

## 📦 Installation

### Requirements
- **Recommended**: Ubuntu 22.04+ / 24.04+
- **Minimum**: 1 CPU / 512 MB RAM / 10 GB disk
- root access and reachability to GitHub and other download sources

### One-liner
```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh                 # standard install (includes BBR)
bash install.sh --harden        # additionally install fail2ban / unattended-upgrades
bash install.sh --update-system # upgrade system packages first
```
The installer: installs dependencies → enables BBR → deploys the project → creates the `proxy` command → creates the subscription dir `/var/www/html/clash` → installs the web dashboard.

---

## 🎮 Usage

Launch the menu:
```bash
proxy
```

Main menu (v3.3.0, simplified):
```
================================
 Proxy Manager v3.3.0
================================
Services — Xray:running | Dashboard:running | Nginx:running
 1. Xray Reality
 2. Clash Subscription & Publishing
 3. Web Dashboard ⭐
 4. Health Check
 5. Node Information
 6. Update
 7. Uninstall
 0. Exit
```

CLI usage:
```bash
proxy             # open the interactive menu
proxy update      # fast-forward update from GitHub and restart services
proxy check       # health check (services / node file / config)
proxy version     # print version
proxy --help      # help
```

> **Uninstall**: `bash uninstall.sh` (keep `data/`) or `bash uninstall.sh --clean` (wipe everything including keys).

---

## 📱 Clash Import
After installation you get a subscription URL with a random token (like `http://SERVER_IP/clash/<token>/config.yaml`; view it in menu 5 or the web dashboard):

In Clash Verge: `Profiles → New Profile → URL → paste the subscription URL`.

---

## 🖥 Web Dashboard
The dashboard **binds to `127.0.0.1:8080` only** by default — it is not exposed publicly. The random password is generated and printed on first setup (`Menu → 3. Web Dashboard → 1`).

Access via SSH tunnel (recommended):
```bash
ssh -L 8080:127.0.0.1:8080 user@SERVER_IP
# then open http://localhost:8080
```

To expose it publicly: `proxy` → 3 → 7 toggles "public access" (binds `0.0.0.0` and opens 8080). Turn it off when not needed, or put a TLS-terminating reverse proxy in front.

Features: service status, resource monitoring, online restart, log viewing, subscription copy, node QR code.

---

## 📂 Project Structure
```
Proxy-Manager
├── README.md            🇨🇳 Chinese
├── README_EN.md         🇺🇸 English
├── LICENSE
├── VERSION
├── install.sh / uninstall.sh / update.sh
├── proxy-manager.sh     main menu entry
├── lib/
│   └── common.sh        shared functions
├── modules/
│   ├── xray.sh          Xray Reality node
│   ├── subscription.sh  Clash subscription + nginx publishing
│   └── panel.sh         web dashboard deployment
├── docs/                docs (docs/legacy/ holds historical material)
├── tests/
│   └── check.sh         health check
└── web/                 FastAPI dashboard
    ├── app.py / auth.py / service.py / qrgen.py
    ├── requirements.txt
    ├── templates/        index.html / login.html
    └── static/           style.css
```

---

## 🔐 Security
- **Never upload** `data/node.env` and `data/web.env`: the former holds `PRIVATE_KEY` / `UUID`, the latter holds the dashboard password.
- **The subscription URL contains a random token and is a node credential** — do not share it publicly. If leaked, regenerate the subscription and rotate `SUB_TOKEN`.
- This repo's `.gitignore` already excludes `data/`, `web/venv/`, `__pycache__/`, `outputs/`.
- Use SSH keys, open only required ports, and keep the system and Xray updated.
- This project gives no guarantee of anonymity or circumvention of local laws; comply with applicable laws and provider rules.

---

## 🛠 Roadmap
- [x] **v3.1** Xray Reality / Mihomo / Clash subscription / DNS optimization
- [x] **v3.2** Web Dashboard / service status / resource monitoring
- [x] **v3.2.1** Login auth / restart & logs / subscription copy / node QR code
- [x] **v3.2.2** Bug fix: install.sh Python deps / dynamic proxy path / Clash xudp / configurable Reality dest
- [x] **v3.2.3** Guidance layer: install.sh auto-installs Web panel & prints access info / webpanel.sh gains start·stop·address·credentials·reset-password / Web entry starred in CLI menu
- [x] **v3.2.8** Security hardening + UI overhaul: random-token subscription path / removed default-credential fallback (login refused without web.env) / dashboard binds 127.0.0.1 by default (public access is opt-in) / restart switched to POST with confirmation / log output HTML-escaped / brand-new dark dashboard theme
- [x] **v3.2.9** Reliability: `proxy update` refreshes panel deps & systemd unit and restarts the panel / install.sh always refreshes the apt index / mihomo download picks assets explicitly (standard build first, compatible fallback) with gzip integrity check + GITHUB_TOKEN support / dedicated nginx site config (auto-rollback on failure, default site restored on uninstall) / login rate limiting
- [x] **v3.2.10** Regression fixes: `update.sh` resolved `BASE_DIR` one level too high, making `proxy update` entirely unusable / `restart_if_active` returned non-zero for stopped services, aborting the update flow / menu no longer exits when a sub-command fails / `env_upsert` rewritten with awk (values containing `&`, `|`, `\` were silently corrupted) / `core.fileMode=false` stops chmod from keeping the work tree permanently dirty and blocking `git pull`
- [x] **v3.3.0** Simplification refactor: removed the Mihomo client and DNS/AdGuard modules (wrong role on a server node, port-53 conflicts, TUN once took down SSH) / removed `server-fix-proxy.sh` and unreferenced config templates / BBR moved into install.sh by default, fail2ban now behind the explicit `--harden` flag / nginx publishing merged into `subscription.sh` (auto-publish after generation) / `webpanel.sh` renamed to `panel.sh` / main menu trimmed from 12 to 7 items / LF enforced via `.gitattributes`
- [ ] **v3.4** Multi-node management / traffic stats / API management

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
