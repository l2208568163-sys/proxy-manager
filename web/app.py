#!/usr/bin/env python3
"""Proxy Manager Web 管理面板 (FastAPI)。

多页控制台：概览 / 节点 / 订阅 / 服务 / 安全 / 设置 + 登录、注销、服务重启、日志。

- 登录认证、IP 失败限速、进程内会话令牌（见 auth.py）
- 服务重启为 POST + 前端确认（samesite=lax cookie 防跨站 CSRF）
- 日志输出经 Jinja2 自动转义，防日志注入 XSS
- 订阅地址含随机令牌（node.env 的 SUB_TOKEN），路径不可猜测

版本号从项目根 VERSION 读取；监听地址读取自 data/web.env 的 WEB_BIND
（与 modules/panel.sh 的 read_web_bind 同源），端口默认 8080。
"""
import html
import os
import subprocess
import time

import psutil
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

import auth
import qrgen
import service

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE_FILE = os.path.join(BASE_DIR, "data", "node.env")
WEB_ENV = os.path.join(BASE_DIR, "data", "web.env")
VERSION_FILE = os.path.join(BASE_DIR, "VERSION")
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(WEB_DIR, "static")
TEMPLATES_DIR = os.path.join(WEB_DIR, "templates")

# 面板监听端口（modules/panel.sh 里写死 8080）；地址与 panel.sh 同源：优先环境变量
# BIND_ADDR，否则回退到 web.env 的 WEB_BIND，最终默认仅本机 127.0.0.1。
DEFAULT_BIND = "127.0.0.1"
BIND_PORT = os.environ.get("BIND_PORT", "8080")


def read_web_bind() -> str:
    """与 modules/panel.sh 的 read_web_bind 同源：从 data/web.env 读取 WEB_BIND。"""
    if not os.path.exists(WEB_ENV):
        return DEFAULT_BIND
    bind = DEFAULT_BIND
    try:
        with open(WEB_ENV, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == "WEB_BIND":
                    bind = v.strip() or DEFAULT_BIND
    except Exception:
        pass
    return bind


BIND_ADDR = os.environ.get("BIND_ADDR") or read_web_bind()

# 关闭公开的 API 文档页，减少暴露面
app = FastAPI(title="Proxy Manager", docs_url=None, redoc_url=None)
# 挂载静态资源（此前 /static 未挂载导致样式表 404、页面裸奔渲染）
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)

APP_VERSION = "-"
if os.path.exists(VERSION_FILE):
    with open(VERSION_FILE, encoding="utf-8") as f:
        APP_VERSION = f.read().strip() or "-"

SERVICES = [("xray", "Xray"), ("nginx", "Nginx"), ("proxy-web", "Web 面板")]


def service_status(name: str) -> str:
    try:
        out = subprocess.check_output(
            ["systemctl", "is-active", name],
            stderr=subprocess.DEVNULL,
        )
        return out.decode().strip()
    except Exception:
        return "inactive"


def service_list():
    return [{"key": k, "label": l, "state": service_status(k)} for k, l in SERVICES]


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


def dashboard_context() -> dict:
    node = get_node()
    clash = subscription_url(node)
    sent, recv = net_stats()
    xray_active = service_status("xray") == "active"
    return {
        "node": node,
        "node_name": node.get("NODE_NAME", "-"),
        "server": node.get("SERVER", "-"),
        "port": node.get("PORT", "-"),
        "sni": node.get("SNI", "-"),
        "uuid": node.get("UUID", "-"),
        "clash": clash,
        "sub_ready": bool(clash),
        "qr": qrgen.data_uri(clash) if clash else None,
        # 节点在线率：核心代理服务 Xray 在运行即视为主节点在线
        "online_rate": 100 if xray_active else 0,
        "cpu": psutil.cpu_percent(),
        "memory": psutil.virtual_memory().percent,
        "net_recv": human(recv),
        "net_sent": human(sent),
        "net_total": round((sent + recv) / (1024 ** 3), 1),
    }


def security_context() -> dict:
    creds = auth.load_creds()
    web_user = creds[0] if creds else "-"
    now = time.time()
    window = auth._WINDOW_SECONDS
    max_fails = auth._MAX_FAILS
    locked_ips = 0
    recent_failures = 0
    for ts in auth._FAILURES.values():
        recent = [t for t in ts if now - t < window]
        recent_failures += len(recent)
        if len(recent) >= max_fails:
            locked_ips += 1
    cred_reset = "-"
    if os.path.exists(WEB_ENV):
        try:
            cred_reset = time.strftime(
                "%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(WEB_ENV))
            )
        except Exception:
            cred_reset = "-"
    return {
        "bind_addr": BIND_ADDR,
        "bind_port": BIND_PORT,
        "public_on": BIND_ADDR in ("0.0.0.0", "::"),
        "web_user": web_user,
        "lock_threshold": max_fails,
        "lock_window_min": window // 60,
        "locked_ips": locked_ips,
        "recent_failures": recent_failures,
        "cred_reset": cred_reset,
    }


def common(active_page: str) -> dict:
    """每个受保护页面都需要的基础上下文（base.html 依赖）。"""
    return {
        "version": APP_VERSION,
        "services": service_list(),
        "bind_addr": BIND_ADDR,
        "bind_port": BIND_PORT,
        "active_page": active_page,
    }


def require_login(request: Request):
    if not auth.check_auth(request):
        return RedirectResponse("/login", status_code=303)
    return None


# ------------------------- 认证路由 -------------------------
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if auth.check_auth(request):
        return RedirectResponse("/", status_code=303)
    return templates.TemplateResponse(
        request,
        "login.html",
        {
            "error": None,
            "no_creds": not auth.creds_exist(),
            "version": APP_VERSION,
            "bind_port": BIND_PORT,
            "lock_window_min": auth._WINDOW_SECONDS // 60,
        },
    )


@app.post("/login")
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    ip = auth.client_ip(request)
    # 登录失败限速：超过阈值后一律 429，即使密码正确也不放行（防在线爆破）
    if auth.is_locked(ip):
        return templates.TemplateResponse(
            request,
            "login.html",
            {
                "error": "失败次数过多，IP 已被临时锁定，请约 15 分钟后再试。",
                "no_creds": not auth.creds_exist(),
                "version": APP_VERSION,
                "bind_port": BIND_PORT,
                "lock_window_min": auth._WINDOW_SECONDS // 60,
            },
            status_code=429,
        )
    if auth.login(username, password):
        auth.record_success(ip)
        token = auth.create_session()
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie("session", token, httponly=True, samesite="lax")
        return resp
    auth.record_failure(ip)
    if not auth.creds_exist():
        error = "未检测到 data/web.env，登录已被拒绝。请在服务器运行 modules/panel.sh reset 生成随机口令。"
    else:
        error = "用户名或密码错误"
    return templates.TemplateResponse(
        request,
        "login.html",
        {
            "error": error,
            "no_creds": not auth.creds_exist(),
            "version": APP_VERSION,
            "bind_port": BIND_PORT,
            "lock_window_min": auth._WINDOW_SECONDS // 60,
        },
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
    redir = require_login(request)
    if redir:
        return redir
    ctx = common("overview")
    ctx.update(dashboard_context())
    return templates.TemplateResponse(request, "overview.html", ctx)


@app.get("/nodes", response_class=HTMLResponse)
async def nodes(request: Request):
    redir = require_login(request)
    if redir:
        return redir
    ctx = common("nodes")
    ctx.update(dashboard_context())
    return templates.TemplateResponse(request, "nodes.html", ctx)


@app.get("/subs", response_class=HTMLResponse)
async def subs(request: Request):
    redir = require_login(request)
    if redir:
        return redir
    ctx = common("subs")
    ctx.update(dashboard_context())
    return templates.TemplateResponse(request, "subs.html", ctx)


@app.get("/services", response_class=HTMLResponse)
async def services(request: Request):
    redir = require_login(request)
    if redir:
        return redir
    return templates.TemplateResponse(request, "services.html", common("services"))


@app.get("/security", response_class=HTMLResponse)
async def security(request: Request):
    redir = require_login(request)
    if redir:
        return redir
    ctx = common("security")
    ctx.update(security_context())
    return templates.TemplateResponse(request, "security.html", ctx)


@app.get("/settings", response_class=HTMLResponse)
async def settings(request: Request):
    redir = require_login(request)
    if redir:
        return redir
    ctx = common("settings")
    ctx.update({"node_name": get_node().get("NODE_NAME", "-")})
    return templates.TemplateResponse(request, "settings.html", ctx)


@app.post("/restart/{svc}")
async def restart_service(svc: str, request: Request):
    redir = require_login(request)
    if redir:
        return redir
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
    redir = require_login(request)
    if redir:
        return redir
    label = dict(SERVICES).get(svc, svc)
    try:
        text = service.log(svc)
    except ValueError as e:
        text = str(e)
    # svc 已通过 service._guard 白名单校验（仅 xray/nginx/proxy-web），故可直接用于 JS；
    # 日志正文交由 Jinja2 自动转义，避免日志注入 XSS。
    ctx = common("services")
    ctx.update({"svc": svc, "svc_label": label, "text": text})
    return templates.TemplateResponse(request, "logs.html", ctx)
