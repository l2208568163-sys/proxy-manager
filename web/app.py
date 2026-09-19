#!/usr/bin/env python3
"""Proxy Manager v3.2.5 Web 管理面板 (FastAPI)。

功能：登录认证、Xray/Mihomo/AdGuardHome 状态与资源监控、服务重启、日志查看、
Clash 订阅一键复制、订阅二维码。路径基于本文件位置自动推导，部署位置无关。
"""
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import subprocess
import psutil
import os

import auth
import service
import qrgen

# BASE_DIR = 项目根目录（web/ 的上一级）
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE_FILE = os.path.join(BASE_DIR, "data", "node.env")
TEMPLATES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")

app = FastAPI(title="Proxy Manager")
templates = Jinja2Templates(directory=TEMPLATES_DIR)


def service_status(name: str) -> str:
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


# ------------------------- 认证路由 -------------------------
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if auth.check_auth(request):
        return RedirectResponse("/")
    return templates.TemplateResponse(request, "login.html", {"error": None})


@app.post("/login")
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    if auth.login(username, password):
        token = auth.create_session()
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie("session", token, httponly=True, samesite="lax")
        return resp
    return templates.TemplateResponse(request, "login.html", {"error": "用户名或密码错误"}, status_code=401)


@app.get("/logout")
async def logout(request: Request):
    token = request.cookies.get("session")
    if token:
        auth.destroy_session(token)
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie("session")
    return resp


# ------------------------- 受保护路由 -------------------------
@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    node = get_node()
    server = node.get("SERVER", "-")
    port = node.get("PORT", "-")
    clash = f"http://{server}/clash/config.yaml" if server != "-" else "-"
    sent, recv = net_stats()
    qr = qrgen.data_uri(clash) if clash != "-" else None
    return templates.TemplateResponse(
        request,
        "index.html",
        {
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
            "qr": qr,
        },
    )


@app.get("/restart/{svc}")
async def restart_service(svc: str, request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    try:
        service.restart(svc)
    except ValueError as e:
        return HTMLResponse(f"<pre>{e}</pre><br><a href='/'>返回</a>", status_code=400)
    return RedirectResponse("/", status_code=303)


@app.get("/logs/{svc}", response_class=HTMLResponse)
async def logs(svc: str, request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    try:
        text = service.log(svc)
    except ValueError as e:
        return HTMLResponse(f"<pre>{e}</pre><br><a href='/'>返回</a>", status_code=400)
    return f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>日志 - {svc}</title>
<link rel="stylesheet" href="/static/style.css"></head>
<body><div class="box">
<h1>日志：{svc}</h1>
<pre class="log">{text}</pre>
<p><a href="/restart/{svc}">重启 {svc}</a> &nbsp; <a href="/">返回</a></p>
</div></body></html>"""
