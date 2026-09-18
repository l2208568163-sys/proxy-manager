# Installation

Run on Ubuntu 22.04 or later as root:

```bash
git clone https://github.com/l2208568163-sys/proxy-manager.git
cd proxy-manager
bash install.sh
```

Use `bash install.sh --update-system` only when you also want system packages upgraded. After installation, run `proxy` to open the manager. The installer does not enable UFW; if UFW is already active, the relevant module opens only its own required port.
