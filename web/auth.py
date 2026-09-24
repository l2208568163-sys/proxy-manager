#!/usr/bin/env python3
"""Proxy Manager Web 登录认证。

凭据从项目 data/web.env 读取（WEB_USER / WEB_PASS），不写死在代码里。
web.env 缺失或无效时拒绝登录（绝不回退默认口令），并提示运行
modules/webpanel.sh reset 生成随机口令。

会话用随机令牌，存于进程内集合，cookie 仅持有令牌。
"""
import os
import secrets

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_ENV = os.path.join(BASE_DIR, "data", "web.env")

# 进程内会话令牌集合（单进程 uvicorn 足够；多 worker 需换外部存储）
SESSIONS = set()


def creds_exist() -> bool:
    return os.path.exists(WEB_ENV)


def load_creds():
    """返回 (user, pw)；web.env 缺失或内容无效时返回 None。"""
    if not creds_exist():
        return None
    user = pw = None
    with open(WEB_ENV, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip()
            if k == "WEB_USER":
                user = v
            elif k == "WEB_PASS":
                pw = v
    if not user or not pw:
        return None
    return user, pw


def check_auth(request) -> bool:
    token = request.cookies.get("session")
    return bool(token) and token in SESSIONS


def login(username: str, password: str) -> bool:
    creds = load_creds()
    if creds is None:
        print("[auth] 拒绝登录: data/web.env 缺失或无效。"
              "请在服务器运行 modules/webpanel.sh reset 生成随机口令。")
        return False
    user, pw = creds
    # 常量时间比较，避免计时侧信道
    return secrets.compare_digest(username, user) and secrets.compare_digest(password, pw)


def create_session() -> str:
    token = secrets.token_hex(16)
    SESSIONS.add(token)
    return token


def destroy_session(token: str) -> None:
    SESSIONS.discard(token)
