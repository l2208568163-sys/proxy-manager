# Installation

Run on Ubuntu 22.04 or later as root:

```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh
```

Use `bash install.sh --update-system` only when you also want system packages upgraded. After installation, run `proxy` to open the manager. The installer does not enable UFW; if UFW is already active, the relevant module opens only its own required port (22/80/443 — port 8080 for the web dashboard stays closed unless you turn on public access, since the dashboard binds 127.0.0.1 by default).

The subscription URL contains a random token (see `docs/architecture.md`); view it with `proxy` → menu 9 or the web dashboard after generating a subscription.
