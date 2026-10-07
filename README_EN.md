# 🚀 Proxy-Manager

<p align="center">
  <b>One-click deployment tool for Xray Reality + Clash subscription on Ubuntu Server</b>
</p>

<p align="center">
  <a href="https://github.com/l2208568163-sys/proxy-manager"><img src="https://img.shields.io/github/stars/l2208568163-sys/proxy-manager" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/l2208568163-sys/proxy-manager" alt="GitHub license"></a>
  <img src="https://img.shields.io/badge/version-3.4.0-blue" alt="Version">
</p>

<p align="center">
  🇺🇸 English | <a href="README.md">🇨🇳 中文</a>
</p>

---

## 📖 Introduction

Proxy-Manager is an automated proxy-node management tool for Ubuntu Server. It turns common deployment and maintenance tasks into a single interactive command.

It helps you deploy:

- **Xray Reality** nodes (VLESS + Reality + Vision)
- **Clash URL subscription** (HTTP subscription file)
- **BBR** network optimization

> Goal: deploy and manage a server proxy environment with one command.

---

## ✨ Features

### 🔥 Xray Reality
- Protocols: VLESS + Reality + Vision Flow + TCP
- Auto-generates: `UUID`, `Private Key`, `Public Key`, `Short ID`
- Picks a free port from `443 / 8443 / 2053 / 2083`
- **WiFi web-auth bypass mode**: open a **separate dedicated node** (Vmess + mKCP, UDP) on gateway-allowed `53 / 67 / 68 / 123`, disguised as **DNS**, bypassing captive portals at cafés/hotels (see the dedicated section below; still fails on deep-inspection networks)
- Validates the Xray config before writing, and generates a VLESS URI + node info file

### 🌐 Clash Subscription
- Compatible with Clash Verge, Clash Meta, Mihomo Party, etc.
- Auto-generates a subscription URL with a **random token**: `http://SERVER_IP/clash/<token>/config.yaml` — the path is unguessable, keeping node credentials safe from scanners
- Paste the URL to import

### 📶 WiFi Web-auth Bypass (Dedicated Node · Vmess + mKCP)
- **Dedicated node**: its own Xray inbound (Vmess + mKCP, **UDP**), coexisting with the main node — separate port, separate UUID
- Port sits on gateway-allowed `53 / 67 / 68 / 123` and disguises traffic as **DNS** (mKCP header = `dns`). Hotspots allow UDP 53 DNS to redirect you to the auth page, so UDP works best (Reality is TCP-only and cannot pass)
- Prefers **53**; if systemd-resolved's stub listener holds it, the script can release it (disable the stub, keep the machine's existing DNS, back up `/etc/resolv.conf` to `.bak.proxy-manager`); it **rolls back automatically** if DNS breaks
- Parameters match 3x-ui defaults: MTU 1350 / TTI 50 / uplink·downlink 20 MB/s / congestion off / read·write buffer 2
- **Core-version compatibility (important)**: since Xray **v26.2.6** the `kcpSettings.header/seed` fields are removed and DNS disguise moved to a `finalmask` UDP mask — and **the mask type name differs across core generations** (v26.2~26.3 use `header-dns`, v26.7+ use `mkcp-legacy`). The script adapts automatically: it tries `mkcp-legacy` first and falls back to `header-dns` when the core rejects it, so both generations work
- Client: import the printed `vmess://` link with **v2rayN / v2rayNG (Xray core)**, enable "DNS proxy / anti-leak" in global mode. clash / sing-box handle UDP:53 disguise poorly, so this node is **not** put into the Clash subscription
- Known limits: some providers (e.g. Alibaba Cloud) block port 53 for personal use; deep-inspection networks (SNI blocking / real DNS proxying) may still fail

### ⚡ System Optimization
- BBR, TCP Fast Open, FQ queue
- Fail2ban and unattended-upgrades (security module)

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

### Backup & restore on re-install
- If `/opt/proxy-manager` already exists, the installer first backs up `data/` to `/opt/proxy-manager-backup-<timestamp>`
- It then lists **all** backups (this run's plus any left over) and asks whether to restore — pick a number, or `0` for a fresh config
- Non-interactive runs (e.g. `curl ... | bash install.sh` with no TTY) auto-restore the **newest** backup so no node is lost
- Skip the prompt with flags: `--restore` (restore newest immediately), `--no-restore` (never restore; backups are kept)

> Restoring overwrites same-named files under `data/` (node keys get replaced) — check the number before pressing Enter.

---

## 🎮 Usage

Launch the menu:
```bash
proxy
```

Main menu:
```
================================
 Proxy Manager v3.4.3
================================
 1. Xray Reality
 2. Clash Subscription
 3. System Optimization
 4. Security Hardening
 5. Web Subscription Service
 6. Health Check
 7. Node Information
 8. Update
 9. Uninstall
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

### Backup handling at uninstall
At the end of uninstall, every `/opt/proxy-manager-backup-*` is listed and you choose:
- `a` = delete all　`n` = keep all (**default**)　`s` = delete selected numbers (e.g. `1 3`)

Backups contain the node keys in `data/` — **deletion is irreversible**. Kept backups will be offered again on the next `install.sh`.

---

## 📱 Clash Import
After installation you get a subscription URL with a random token (like `http://SERVER_IP/clash/<token>/config.yaml`; view it in menu 7):

In Clash Verge: `Profiles → New Profile → URL → paste the subscription URL`.

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
│   ├── system.sh        system optimization
│   ├── security.sh      security hardening
│   └── web.sh           Nginx subscription service
├── configs/             reference templates
├── docs/                docs
└── tests/
    └── check.sh         health check
```

---

## 🔐 Security
- **Never upload** `data/node.env`: it holds `PRIVATE_KEY` / `UUID`.
- **The subscription URL contains a random token and is a node credential** — do not share it publicly. If leaked, regenerate the subscription and rotate `SUB_TOKEN`.
- This repo's `.gitignore` already excludes `data/node.env`, `__pycache__/`.
- Use SSH keys, open only required ports, and keep system / Xray updated.
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
- [x] **v3.3.0** Web-auth bypass (port 53 + fragment) / **removed Web dashboard** (FastAPI panel and modules/webpanel.sh deleted) / docs updated
- [x] **v3.4.3** **fixed WiFi node failing to start on new Xray cores**: v26.2.6+ removed `kcpSettings.header/seed`; DNS disguise moved to a `finalmask` UDP mask, and the mask type name is incompatible across generations (v26.2~26.3 `header-dns` vs v26.7+ `mkcp-legacy`) — config writing now tries and falls back automatically (verified against a real v26.3.27 core)
- [x] **v3.4.2** **fixed "program quits right after selecting a feature"**: main menu wraps every module with `|| module_failed` so a module error no longer kills the whole program and the error stays on screen; Xray menu 1/6/7, load_node_data, write_xray_config and restart_xray_and_wait now fail with readable errors and graceful returns instead of relying on set -e
- [x] **v3.4.1** **interactive backup management**: on install, list this run's + leftover backups and let the user pick whether to restore (new `--restore` / `--no-restore`; non-interactive runs auto-restore newest) / at uninstall, ask about leftover backups (delete all / keep all / delete selected numbers); WiFi web-auth bypass switched to Vmess + mKCP (UDP + DNS disguise)
- [x] **v3.4.0** **removed entire DNS module** (AdGuard Home + system DNS optimization, modules/dns.sh deleted) / **removed Mihomo client module** (modules/mihomo.sh deleted) / **renamed "Web-auth bypass" to "WiFi web-auth bypass" and made it a dedicated node** (own inbound, own keys and port, does not overwrite the main node; can release port 53) / main menu rearranged
- [ ] Multi-node management / traffic stats / API management

> Note: as of v3.3.0 the Web dashboard (FastAPI + webpanel.sh) is fully removed; as of **v3.4.0 the entire DNS module (AdGuard Home + system DNS optimization, modules/dns.sh) is also removed** and the main menu is rearranged accordingly. The v3.2-series entries referencing the dashboard are kept only as historical changelog and are no longer part of the product.

---

## 📄 License
[MIT License](LICENSE)

---

<p align="center">Made with ❤️ by Proxy-Manager</p>
