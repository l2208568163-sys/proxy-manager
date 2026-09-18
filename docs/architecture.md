# Architecture

`proxy-manager.sh` is the single command entry point. Xray generates and stores node metadata in `/opt/proxy-manager/data/node.env` with owner-only permissions. The subscription module produces `/var/www/html/clash/config.yaml`; Nginx exposes it at `/clash/config.yaml`. Mihomo is treated as a separate client: it imports a user-supplied subscription and does not automatically route the server through its own Xray node.
