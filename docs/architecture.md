# Architecture

`proxy-manager.sh` is the single command entry point. Xray generates and stores node metadata in `/opt/proxy-manager/data/node.env` with owner-only permissions.

The subscription module produces the Clash config at `/var/www/html/clash/<random-token>/config.yaml`; Nginx (default site root `/var/www/html`) exposes it at `/clash/<random-token>/config.yaml`. The token (`SUB_TOKEN` in `node.env`) is generated once with `openssl rand -hex 16` and makes the subscription URL unguessable — the config contains the node UUID, which is the only VLESS credential, so a guessable fixed path would let anyone on the internet use the node for free. Regenerating the subscription (`menu 2`) keeps the token; remove `SUB_TOKEN` from `node.env` and regenerate to rotate it.

Mihomo is treated as a separate client: it imports a user-supplied subscription and does not automatically route the server through its own Xray node.

The web dashboard (FastAPI, systemd unit `proxy-web`) reads the same `node.env`. It binds `127.0.0.1:8080` by default (`WEB_BIND` in `data/web.env`; the `webpanel.sh` menu can switch it to `0.0.0.0`, which also opens UFW 8080). Credentials come from `data/web.env`; if that file is missing, login is refused rather than falling back to default credentials. Service restart is a POST route guarded by the session cookie (`SameSite=Lax`) plus a client-side confirmation; log output is HTML-escaped before rendering.
