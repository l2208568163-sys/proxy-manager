#!/usr/bin/env python3
"""Proxy Manager v3.2 Web 管理面板 (FastAPI)。

读取项目 data/node.env，展示 Xray / Mihomo / AdGuardHome 运行状态与
服务器资源占用。路径基于本文件位置自动推导，部署到 /root/proxy-manager
或 /opt/proxy-manager 均可，无需硬编码。
"""
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
import subprocess
import psutil
import os

# BASE_DIR = 项目根目录（web/ 的上一级）
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE_FILE = os.path.join(BASE_DIR, "data", "node.env")
TEMPLATES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")

app = FastAPI(title="Proxy Manager")
templates = Jinja2Templates(directory=TEMPLATES_DIR)


def service_status(name: str) -> str:
    """返回 systemctl is-active 的原始状态（active/inactive/unknown...）。"""
    try:
        out = subprocess.check_output(
            ["systemctl", "is-active", name],
            stderr=subprocess.DEVNULL,
        )
        return out.decode().strip()
    except Exception:
        return "inactive"


def status_label(state: str) -> str:
    return "🟢 Running" if state == "active" else "🔴 Stopped"


def get_node() -> dict:
    """解析 data/node.env（KEY=VALUE，忽略注释与空行）。"""
    data: dict = {}
    if os.path.exists(NODE_FILE):
        with open(NODE_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip()
    return data


def net_stats():
    try:
        c = psutil.net_io_counters()
        return c.bytes_sent, c.bytes_recv
    except Exception:
        return 0, 0


def human(n: float) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    node = get_node()
    server = node.get("SERVER", "-")
    port = node.get("PORT", "-")
    clash = f"http://{server}/clash/config.yaml" if server != "-" else "-"
    sent, recv = net_stats()
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "xray": status_label(service_status("xray")),
            "mihomo": status_label(service_status("mihomo")),
            "dns": status_label(service_status("AdGuardHome")),
            "server": server,
            "port": port,
            "clash": clash,
            "cpu": psutil.cpu_percent(),
            "memory": psutil.virtual_memory().percent,
            "net_recv": human(recv),
            "net_sent": human(sent),
        },
    )
