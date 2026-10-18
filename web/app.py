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
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

import auth
import qrgen
import service
import perf

# 启动后台性能采集线程（CPU/内存/磁盘/网络/负载快照 + 历史趋势）
perf.start()

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE_FILE = os.path.join(BASE_DIR, "data", "node.env")
WEB_ENV = os.path.join(BASE_DIR, "data", "web.env")
VERSION_FILE = os.path.join(BASE_DIR, "VERSION")
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(WEB_DIR, "static")
TEMPLATES_DIR = os.path.join(WEB_DIR, "templates")
STYLE_FILE = os.path.join(STATIC_DIR, "style.css")

# 内联样式：与参考原型（单文件、内嵌 <style>）一致，保证「直接打开 HTML」也能正常渲染，
# 不再依赖 /static/style.css 绝对路径（file:// 或静态预览下会 404 导致页面裸奔）。
try:
    with open(STYLE_FILE, encoding="utf-8") as _f:
        APP_CSS = _f.read()
except Exception:
    APP_CSS = ""

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
# 让所有模板（base / login / result）都能直接内联同一份设计系统 CSS
templates.env.globals["APP_CSS"] = APP_CSS

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


def human(n: float) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


def fmt_uptime(seconds: float) -> str:
    """运行时长人性化显示（性能监视模块用）。"""
    s = int(seconds or 0)
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    return (f"{d}天 " if d else "") + f"{h}小时{m}分"


def login_stats() -> dict:
    """登录失败限速实时统计（security_context 与 dashboard_context 共用）。"""
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
    return {
        "lock_threshold": max_fails,
        "lock_window_min": window // 60,
        "locked_ips": locked_ips,
        "recent_failures": recent_failures,
    }


def dashboard_context() -> dict:
    node = get_node()
    clash = subscription_url(node)
    # 性能数据全部来自后台采集线程的真实快照
    # （修复原 psutil.cpu_percent() 无 interval 导致 CPU% 恒≈0 的采样缺陷）
    snap = perf.snapshot()
    xray_active = snap.get("online", 0) == 1
    stats = login_stats()
    # 概览「最近活动」时间线：用真实可推导的状态拼装，不做假时间戳
    activity = []
    if xray_active:
        activity.append({"title": "Xray 节点运行中", "time": "实时", "kind": "ok"})
    else:
        activity.append({"title": "Xray 节点离线", "time": "实时", "kind": "bad"})
    if clash:
        activity.append({"title": "订阅令牌有效", "time": node.get("CREATED") or "—", "kind": "ok"})
    else:
        activity.append({"title": "订阅尚未生成", "time": "—", "kind": "warn"})
    if stats["locked_ips"]:
        activity.append({"title": f"{stats['locked_ips']} 个 IP 被临时锁定", "time": f"近 {stats['lock_window_min']} 分钟", "kind": "warn"})
    elif stats["recent_failures"]:
        activity.append({"title": f"近 {stats['lock_window_min']} 分钟 {stats['recent_failures']} 次登录失败", "time": "当前", "kind": "warn"})
    else:
        activity.append({"title": "登录防护正常，无异常", "time": "当前", "kind": "ok"})
    net_total = round(snap.get("net_in_total_gb", 0) + snap.get("net_out_total_gb", 0), 1)
    return {
        "node": node,
        "node_name": node.get("NODE_NAME", "-"),
        "node_created": node.get("CREATED") or "-",
        "server": node.get("SERVER", "-"),
        "port": node.get("PORT", "-"),
        "sni": node.get("SNI", "-"),
        "uuid": node.get("UUID", "-"),
        "clash": clash,
        "sub_ready": bool(clash),
        "qr": qrgen.data_uri(clash) if clash else None,
        # 节点在线率：核心代理服务 Xray 在运行即视为主节点在线
        "online_rate": 100 if xray_active else 0,
        # ---- 性能监视（后台线程真实采样）----
        "cpu": snap.get("cpu", 0.0),
        "memory": snap.get("mem", 0.0),
        "mem_used_gb": snap.get("mem_used_gb", 0.0),
        "mem_total_gb": snap.get("mem_total_gb", 0.0),
        "swap": snap.get("swap", 0.0),
        "disk": snap.get("disk", 0.0),
        "disk_used_gb": snap.get("disk_used_gb", 0.0),
        "disk_total_gb": snap.get("disk_total_gb", 0.0),
        "load1": snap.get("load1", 0.0),
        "load5": snap.get("load5", 0.0),
        "load15": snap.get("load15", 0.0),
        "uptime_h": fmt_uptime(snap.get("uptime", 0)),
        "net_recv": human(snap.get("net_in_total_gb", 0) * 1024 ** 3),
        "net_sent": human(snap.get("net_out_total_gb", 0) * 1024 ** 3),
        "net_total": net_total,
        "net_in_rate_h": human(snap.get("net_in_rate", 0)) + "/s",
        "net_out_rate_h": human(snap.get("net_out_rate", 0)) + "/s",
        # ---- sparkline 真实走势（后台历史队列驱动，替换原硬编码演示折线）----
        "cpu_spark": perf.spark("cpu", lo=0, hi=100),
        "mem_spark": perf.spark("mem", lo=0, hi=100),
        "disk_spark": perf.spark("disk", lo=0, hi=100),
        "net_spark": perf.spark("net"),
        "online_spark": perf.spark("online", lo=0, hi=1),
        "lock_window_min": stats["lock_window_min"],
        "locked_ips": stats["locked_ips"],
        "recent_failures": stats["recent_failures"],
        "activity": activity,
    }


def security_context() -> dict:
    creds = auth.load_creds()
    web_user = creds[0] if creds else "-"
    stats = login_stats()
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
        "lock_threshold": stats["lock_threshold"],
        "lock_window_min": stats["lock_window_min"],
        "locked_ips": stats["locked_ips"],
        "recent_failures": stats["recent_failures"],
        "cred_reset": cred_reset,
    }


def common(active_page: str) -> dict:
    """每个受保护页面都需要的基础上下文（base.html 依赖）。"""
    stats = login_stats()
    # 顶栏铃铛真实告警数：被锁定 IP 数 +（有失败记录但尚无锁定时计 1），替换原硬编码演示值
    alert_count = stats["locked_ips"] + (
        1 if stats["recent_failures"] and not stats["locked_ips"] else 0
    )
    return {
        "version": APP_VERSION,
        "services": service_list(),
        "bind_addr": BIND_ADDR,
        "bind_port": BIND_PORT,
        "active_page": active_page,
        "alert_count": alert_count,
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
    ctx = common("services")
    # 服务页内联展示 Xray 日志查看器（与参考原型一致），日志正文由 Jinja2 自动转义
    try:
        ctx["log_text"] = service.log("xray")
    except Exception:
        ctx["log_text"] = "（暂无可读取的日志）"
    return templates.TemplateResponse(request, "services.html", ctx)


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


@app.get("/api/metrics")
async def api_metrics(request: Request):
    """实时性能指标 JSON（性能监视模块数据源，前端每 3s 轮询刷新）。

    需登录；未登录返回 401 JSON 而非 303 跳转，避免 fetch 跟随重定向拿到 HTML。
    """
    redir = require_login(request)
    if redir:
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    snap = perf.snapshot()
    return {
        "cpu": snap.get("cpu", 0.0),
        "mem": snap.get("mem", 0.0),
        "disk": snap.get("disk", 0.0),
        "mem_used_gb": snap.get("mem_used_gb", 0.0),
        "mem_total_gb": snap.get("mem_total_gb", 0.0),
        "disk_used_gb": snap.get("disk_used_gb", 0.0),
        "disk_total_gb": snap.get("disk_total_gb", 0.0),
        "net_in_rate": snap.get("net_in_rate", 0.0),
        "net_out_rate": snap.get("net_out_rate", 0.0),
        "net_in_total_gb": snap.get("net_in_total_gb", 0.0),
        "net_out_total_gb": snap.get("net_out_total_gb", 0.0),
        "load1": snap.get("load1", 0.0),
        "load5": snap.get("load5", 0.0),
        "load15": snap.get("load15", 0.0),
        "uptime": snap.get("uptime", 0.0),
        "online": snap.get("online", 0),
        # sparkline 直接返回服务端算好的 points，前端只管贴上去
        "cpu_spark": perf.spark("cpu", lo=0, hi=100),
        "mem_spark": perf.spark("mem", lo=0, hi=100),
        "disk_spark": perf.spark("disk", lo=0, hi=100),
        "net_spark": perf.spark("net"),
        "online_spark": perf.spark("online", lo=0, hi=1),
    }
