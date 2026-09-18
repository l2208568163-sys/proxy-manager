#!/usr/bin/env python3
"""节点/订阅二维码，生成 base64 data URI（不落盘，避免临时文件与仓库泄露）。"""
import base64
import io

try:
    import qrcode
    HAVE_QR = True
except Exception:
    HAVE_QR = False


def data_uri(url: str):
    """返回可直接放进 <img src> 的 data URI；不可用或 url 为空时返回 None。"""
    if not HAVE_QR or not url:
        return None
    img = qrcode.make(url)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{b64}"
