"""后台性能采集器（性能监视模块核心）。

独立守护线程周期性采样服务器真实指标，并向外提供：
- snapshot()：当前实时快照（CPU/内存/交换/磁盘/网络/负载/运行时长/节点在线）。
- 历史队列：用于概览页 sparkline 展示真实走势。

修复点：
- psutil.cpu_percent() 无 interval 时首调返回 0，且每次调用只测量与上次调用之间的极短间隔，
  导致 CPU% 长期≈0。这里改用线程内 cpu_percent(interval=1.0) 阻塞采样，得到真实利用率。
- 历史由后台线程沉淀，避免每次 HTTP 请求都重新测量（也避免多路由并发调用相互干扰）。
"""
import os
import time
import threading
import collections

import psutil

HISTORY_LEN = 60  # 约 2 分钟（采样周期 ~2s）

_cpu = collections.deque(maxlen=HISTORY_LEN)
_mem = collections.deque(maxlen=HISTORY_LEN)
_disk = collections.deque(maxlen=HISTORY_LEN)
_net = collections.deque(maxlen=HISTORY_LEN)     # 入站速率 bytes/s
_online = collections.deque(maxlen=HISTORY_LEN)   # 节点（Xray）在线 0/1

_latest = {}
_prev_net = None
_prev_ts = 0.0
_lock = threading.Lock()
_started = False


def _safe(fn, default):
    try:
        return fn()
    except Exception:
        return default


def _sample():
    global _prev_net, _prev_ts
    ts = time.time()

    # CPU：阻塞 1s 的真实区间采样（修复首值为 0 / 间隔过短导致恒≈0 的问题）
    cpu = _safe(lambda: psutil.cpu_percent(interval=1.0), _latest.get("cpu", 0.0))

    vm = _safe(psutil.virtual_memory, None)
    mem = vm.percent if vm else 0.0
    mem_used_gb = (vm.used / (1024 ** 3)) if vm else 0.0
    mem_total_gb = (vm.total / (1024 ** 3)) if vm else 0.0

    sm = _safe(psutil.swap_memory, None)
    swap = sm.percent if sm else 0.0

    du = _safe(lambda: psutil.disk_usage("/"), None)
    disk = du.percent if du else 0.0
    disk_used_gb = (du.used / (1024 ** 3)) if du else 0.0
    disk_total_gb = (du.total / (1024 ** 3)) if du else 0.0

    net = _safe(psutil.net_io_counters, None)
    net_in_rate = net_out_rate = 0.0
    net_in_total_gb = (net.bytes_recv / (1024 ** 3)) if net else 0.0
    net_out_total_gb = (net.bytes_sent / (1024 ** 3)) if net else 0.0
    if net and _prev_net is not None and ts > _prev_ts:
        dt = ts - _prev_ts
        net_in_rate = max(0.0, (net.bytes_recv - _prev_net[0]) / dt)
        net_out_rate = max(0.0, (net.bytes_sent - _prev_net[1]) / dt)
    if net:
        _prev_net = (net.bytes_recv, net.bytes_sent)
        _prev_ts = ts

    try:
        load1, load5, load15 = os.getloadavg()
    except Exception:
        load1 = load5 = load15 = 0.0

    # 节点在线：以 Xray 服务是否 active 为准（轻量 subprocess，2s 一次无压力）
    online = 0
    try:
        import subprocess
        out = subprocess.run(
            ["systemctl", "is-active", "xray"],
            capture_output=True, text=True, timeout=2,
        )
        online = 1 if out.stdout.strip() == "active" else 0
    except Exception:
        online = _latest.get("online", 0)

    uptime = _safe(lambda: time.time() - psutil.boot_time(), 0.0)

    snap = {
        "cpu": round(cpu, 1),
        "mem": round(mem, 1),
        "mem_used_gb": round(mem_used_gb, 2),
        "mem_total_gb": round(mem_total_gb, 2),
        "swap": round(swap, 1),
        "disk": round(disk, 1),
        "disk_used_gb": round(disk_used_gb, 2),
        "disk_total_gb": round(disk_total_gb, 2),
        "net_in_rate": net_in_rate,
        "net_out_rate": net_out_rate,
        "net_in_total_gb": round(net_in_total_gb, 2),
        "net_out_total_gb": round(net_out_total_gb, 2),
        "load1": round(load1, 2),
        "load5": round(load5, 2),
        "load15": round(load15, 2),
        "online": online,
        "uptime": uptime,
        "ts": ts,
    }
    with _lock:
        _cpu.append(cpu)
        _mem.append(mem)
        _disk.append(disk)
        _net.append(net_in_rate)
        _online.append(online)
        _latest.clear()
        _latest.update(snap)


def _loop():
    while True:
        try:
            _sample()
        except Exception:
            pass
        time.sleep(1.0)  # 采样阻塞 ~1s + 休眠 1s ≈ 2s 周期


def start():
    """启动后台采集线程（幂等，仅首次生效）。"""
    global _started
    if _started:
        return
    _started = True
    _safe(lambda: psutil.cpu_percent(interval=0.1), 0.0)  # 预热，避免首值 0
    t = threading.Thread(target=_loop, daemon=True)
    t.start()


def snapshot():
    with _lock:
        return dict(_latest)


def _hist(name):
    with _lock:
        return list({
            "cpu": _cpu, "mem": _mem, "disk": _disk,
            "net": _net, "online": _online,
        }[name])


def spark(name, w=90, h=34, pad=3, lo=None, hi=None):
    """把历史序列转成 SVG polyline 的 points 字符串（百分比指标传 lo=0,hi=100）。"""
    vals = _hist(name)
    if not vals:
        return ""
    if lo is None or hi is None:
        lo, hi = min(vals), max(vals)
    rng = (hi - lo) or 1.0
    n = len(vals)
    step = (w - 2 * pad) / max(n - 1, 1)
    pts = []
    for i, v in enumerate(vals):
        x = pad + step * i
        y = (h - pad) - (h - 2 * pad) * ((v - lo) / rng)
        pts.append(f"{x:.1f},{y:.1f}")
    return " ".join(pts)
