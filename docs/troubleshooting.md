# Troubleshooting

- Run `proxy check` to validate available services and configuration files.
- Use `systemctl status xray`, `systemctl status mihomo`, or `systemctl status nginx` for service logs.
- If a subscription URL is unreachable, enable the Web subscription service in `proxy`, confirm Nginx is active, and ensure TCP port 80 is allowed by the host firewall or cloud security group.
- The subscription URL contains a random token (since v3.2.8). View the current URL via `proxy` → menu 9, the web dashboard, or `modules/subscription.sh show`; the old fixed `/clash/config.yaml` path intentionally returns 404. If your client still has the old URL, re-copy the new one from the dashboard or regenerate the subscription.
- If the web dashboard refuses login with "未检测到 data/web.env", generate fresh credentials with `modules/webpanel.sh reset`. The dashboard binds 127.0.0.1 by default — use an SSH tunnel, or enable public access from `proxy` → 12 → 7.
- If Xray fails validation, rerun the Xray module to generate a fresh Reality key pair and configuration.
