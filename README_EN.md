# 🚀 Proxy-Manager

<p align="center">
  <b>One-click deployment tool for Xray Reality + Mihomo + Clash subscription + Web dashboard on Ubuntu Server</b>
</p>

<p align="center">
  <a href="https://github.com/l2208568163-sys/proxy-manager"><img src="https://img.shields.io/github/stars/l2208568163-sys/proxy-manager" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/l2208568163-sys/proxy-manager" alt="GitHub license"></a>
  <img src="https://img.shields.io/badge/version-3.2.9-blue" alt="Version">
</p>

<p align="center">
  🇺🇸 English | <a href="README.md">🇨🇳 中文</a>
</p>

---

## 📖 Introduction

Proxy-Manager is an automated proxy-node management tool for Ubuntu Server. It turns common deployment and maintenance tasks into a single interactive command.

It helps you deploy:

- **Xray Reality** nodes (VLESS + Reality + Vision)
- **Mihomo** (Clash Meta) client
- **Clash URL subscription** (HTTP subscription file)
- **AdGuard Home** DNS
- **BBR** network optimization
- **Web management dashboard** (since v3.2, with login auth)

> Goal: deploy and manage a server proxy environment with one command.

---

## ✨ Features

### 🔥 Xray Reality
- Protocols: VLESS + Reality + Vision Flow + TCP
- Auto-generates: `UUID`, `Private Key`, `Public Key`, `Short ID`
- Picks a free port from `443 / 8443 / 2053 / 2083`
- Validates the Xray config before writing, and generates a VLESS URI + node info file

### 🌐 Clash Subscription
- Compatible with Clash Verge, Clash Meta, Mihomo Party, etc.
- Auto-generates a subscription URL with a **random token**: `http://SERVER_IP/clash/<token>/config.yaml` — the path is unguessable, keeping node credentials safe from scanners
- Paste the URL to import

### 🚀 Mihomo
- TUN mode, Fake-IP DNS, auto-routing, rule-based split
- Installs the core first, then validates the subscription URL before starting

### 🛡 DNS Optimization
- System DNS (Cloudflare + opportunistic DoT)
- Optional AdGuard Home (DoH / DNS cache)

### ⚡ System Optimization
- BBR, TCP Fast Open, FQ queue
- Fail2ban and unattended-upgrades (security module)

### 🖥 Web Dashboard (v3.2 / v3.2.1)
- Service status, CPU, memory, network monitoring
- **Login auth** (random session token; credentials in `data/web.env`)
- Restart services and view Xray/Mihomo logs online
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
bash install.sh
```
The installer: installs dependencies → deploys the project → creates the `proxy` command → creates the subscription dir `/var/www/html/clash`.

---

## 🎮 Usage

Launch the menu:
```bash
proxy
```

Main menu:
```
================================
 Proxy Manager v3.2.1
================================
 1. Xray Reality
 2. Clash Subscription
 3. Mihomo
 4. DNS
 5. System Optimization
 6. Security Hardening
 7. Web Subscription Service
 8. Health Check
 9. Node Information
10. Update
11. Uninstall
12. Web Dashboard
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
After installation you get a subscription URL with a random token (like `http://SERVER_IP/clash/<token>/config.yaml`; view it in menu 9 or the web dashboard):

In Clash Verge: `Profiles → New Profile → URL → paste the subscription URL`.

---

## 🖥 Web Dashboard
The dashboard **binds to `127.0.0.1:8080` only** by default — it is not exposed publicly. The random password is generated and printed on first setup (`Menu → 12. Web Dashboard → 1`).

Access via SSH tunnel (recommended):
```bash
ssh -L 8080:127.0.0.1:8080 user@SERVER_IP
# then open http://localhost:8080
```

To expose it publicly: `proxy` → 12 → 7 toggles "public access" (binds `0.0.0.0` and opens 8080). Turn it off when not needed, or put a TLS-terminating reverse proxy in front.

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
│   ├── xray.sh          Xray Reality
│   ├── subscription.sh  Clash subscription
│   ├── mihomo.sh        Mihomo client
│   ├── dns.sh           DNS / AdGuard Home
│   ├── system.sh        system optimization
│   ├── security.sh      security hardening
│   ├── web.sh           Nginx subscription service
│   └── webpanel.sh      Web dashboard deployment
├── configs/             reference templates
├── docs/                docs
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
- This repo's `.gitignore` already excludes `data/web.env`, `data/node.env`, `web/venv/`, `__pycache__/`.
- Use SSH keys, open only required ports, and keep system / Xray / Mihomo / AdGuard Home updated.
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
- [ ] **v3.3** Multi-node management / traffic stats / API management

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
