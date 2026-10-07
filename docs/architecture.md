# Architecture

`proxy-manager.sh` is the single command entry point. Xray generates and stores node metadata in `/opt/proxy-manager/data/node.env` with owner-only permissions.

The subscription module produces the Clash config at `/var/www/html/clash/<random-token>/config.yaml`; Nginx (default site root `/var/www/html`) exposes it at `/clash/<random-token>/config.yaml`. The token (`SUB_TOKEN` in `node.env`) is generated once with `openssl rand -hex 16` and makes the subscription URL unguessable — the config contains the node UUID, which is the only VLESS credential, so a guessable fixed path would let anyone on the internet use the node for free. Regenerating the subscription (`menu 2`) keeps the token; remove `SUB_TOKEN` from `node.env` and regenerate to rotate it.

Xray runs as the server-side node only. Client cores (Clash Verge, v2rayN, etc.) consume the subscription directly — the project no longer ships a bundled client module.
