#!/usr/bin/env python3
"""Proxy Manager Web 管理面板 (FastAPI)。

功能：登录认证、服务状态与资源监控、服务重启（POST + 前端确认）、日志查看
（输出经 HTML 转义，防日志注入 XSS）、订阅一键复制与二维码。

- 版本号统一从项目根 VERSION 文件读取，不在模板里硬编码。
- 订阅地址包含随机令牌（node.env 的 SUB_TOKEN），路径不可猜测。
"""
import html
import os
import subprocess

import psutil
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

import auth
import qrgen
import service

# BASE_DIR = 项目根目录（web/ 的上一级）
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE_FILE = os.path.join(BASE_DIR, "data", "node.env")
VERSION_FILE = os.path.join(BASE_DIR, "VERSION")
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(WEB_DIR, "static")
TEMPLATES_DIR = os.path.join(WEB_DIR, "templates")

# 关闭公开的 API 文档页，减少暴露面
app = FastAPI(title="Proxy Manager", docs_url=None, redoc_url=None)
# 挂载静态资源（此前 /static 未挂载导致样式表 404、页面裸奔渲染）
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)

APP_VERSION = "-"
if os.path.exists(VERSION_FILE):
    with open(VERSION_FILE, encoding="utf-8") as f:
        APP_VERSION = f.read().strip() or "-"

SERVICES = [("xray", "Xray"), ("mihomo", "Mihomo"), ("AdGuardHome", "AdGuard DNS")]


def service_status(name: str) -> str:
    try:
        out = subprocess.check_output(
            ["systemctl", "is-active", name],
            stderr=subprocess.DEVNULL,
        )
        return out.decode().strip()
    except Exception:
        return "inactive"


def get_node() -> dict:
    data: dict = {}
    if os.path.exists(NODE_FILE):
        with open(NODE_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip()
    return data


def subscription_url(node: dict):
    """订阅地址含随机令牌；SERVER 或 SUB_TOKEN 缺失（旧版 node.env）时返回 None。"""
    server = node.get("SERVER")
    token = node.get("SUB_TOKEN")
    if server and token:
        return f"http://{server}/clash/{token}/config.yaml"
    return None


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
        return RedirectResponse("/", status_code=303)
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": None, "no_creds": not auth.creds_exist(), "version": APP_VERSION},
    )


@app.post("/login")
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    if auth.login(username, password):
        token = auth.create_session()
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie("session", token, httponly=True, samesite="lax")
        return resp
    if not auth.creds_exist():
        error = "未检测到 data/web.env，登录已被拒绝。请在服务器运行 modules/webpanel.sh reset 生成随机口令。"
    else:
        error = "用户名或密码错误"
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": error, "no_creds": not auth.creds_exist(), "version": APP_VERSION},
        status_code=401,
    )


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
    clash = subscription_url(node)
    sent, recv = net_stats()
    services = [
        {"key": key, "label": label, "state": service_status(key)}
        for key, label in SERVICES
    ]
    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "version": APP_VERSION,
            "services": services,
            "server": node.get("SERVER", "-"),
            "port": node.get("PORT", "-"),
            "sni": node.get("SNI", "-"),
            "node_name": node.get("NODE_NAME", "-"),
            "uuid": node.get("UUID", "-"),
            "clash": clash,
            "sub_ready": bool(clash),
            "qr": qrgen.data_uri(clash) if clash else None,
            "cpu": psutil.cpu_percent(),
            "memory": psutil.virtual_memory().percent,
            "net_recv": human(recv),
            "net_sent": human(sent),
        },
    )


@app.post("/restart/{svc}")
async def restart_service(svc: str, request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    # 重启改为 POST（配合 samesite=lax cookie 防跨站触发），并完整处理失败情况
    safe = html.escape(svc)
    try:
        service.restart(svc)
        ok, message = True, f"{safe} 已重启。"
    except ValueError as e:
        ok, message = False, html.escape(str(e))
    except subprocess.CalledProcessError:
        ok, message = False, f"{safe} 重启失败（systemctl 返回非零），请查看系统日志。"
    except Exception as e:
        ok, message = False, f"{safe} 重启出错：{html.escape(str(e))}"
    return templates.TemplateResponse(
        request,
        "result.html",
        {"title": "服务重启", "ok": ok, "message": message, "version": APP_VERSION},
        status_code=200 if ok else 500,
    )


@app.get("/logs/{svc}", response_class=HTMLResponse)
async def logs(svc: str, request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    try:
        text = service.log(svc)
    except ValueError as e:
        text = str(e)
    # journalctl 输出可能包含攻击者可控内容（如请求路径写入日志），必须转义防 XSS
    safe_svc = html.escape(svc)
    safe_text = html.escape(text)
    return f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>日志 - {safe_svc}</title>
<link rel="stylesheet" href="/static/style.css"></head>
<body><main class="wrap"><div class="card log-card">
<h2>日志：{safe_svc}</h2>
<pre class="log">{safe_text}</pre>
<div class="log-actions">
<form method="post" action="/restart/{safe_svc}" onsubmit="return confirm('确认重启 {safe_svc} 吗？')"><button class="btn" type="submit">重启 {safe_svc}</button></form>
<a class="btn ghost" href="/">返回面板</a>
</div>
</div></main></body></html>"""
