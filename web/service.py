#!/usr/bin/env python3
"""服务控制：重启/停止/启动/查看日志。

对所有服务名做白名单校验，防止通过 URL 路径越权操作任意 systemd 单元。
"""
import subprocess

ALLOWED = {"xray", "mihomo", "AdGuardHome", "proxy-web"}


def _guard(service: str) -> None:
    if service not in ALLOWED:
        raise ValueError(f"不允许操作的服务: {service}")


def restart(service: str) -> None:
    _guard(service)
    subprocess.run(["systemctl", "restart", service], check=True)


def stop(service: str) -> None:
    _guard(service)
    subprocess.run(["systemctl", "stop", service], check=True)


def start(service: str) -> None:
    _guard(service)
    subprocess.run(["systemctl", "start", service], check=True)


def log(service: str, lines: int = 50) -> str:
    _guard(service)
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", service, "-n", str(lines), "--no-pager"],
            stderr=subprocess.DEVNULL,
        )
        return out.decode(errors="replace")
    except Exception as e:
        return f"无法读取日志: {e}"
