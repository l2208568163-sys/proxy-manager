# Troubleshooting

- Run `proxy check` to validate available services and configuration files.
- Use `systemctl status xray`, `systemctl status mihomo`, or `systemctl status nginx` for service logs.
- If a subscription URL is unreachable, enable the Web subscription service in `proxy`, confirm Nginx is active, and ensure TCP port 80 is allowed by the host firewall or cloud security group.
- If Xray fails validation, rerun the Xray module to generate a fresh Reality key pair and configuration.
