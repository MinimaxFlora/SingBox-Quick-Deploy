#!/usr/bin/env python3
"""SBQD subscription server.

仅使用 Python 标准库，按 User-Agent 返回不同客户端格式的订阅文件，
并提供只读状态面板。所有配置来自环境变量，不读取 state.json。
"""
from __future__ import annotations

import base64
import hmac
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(os.environ.get("SBQD_SUB_ROOT", "/etc/sbqd/sub")).resolve()
TOKEN = os.environ.get("SBQD_SUB_TOKEN", "")
HOST = os.environ.get("SBQD_SUB_HOST", "0.0.0.0")
PORT = int(os.environ.get("SBQD_SUB_PORT", "0") or 0)
CERT = os.environ.get("SBQD_SUB_CERT", "")
KEY = os.environ.get("SBQD_SUB_KEY", "")
CLASH = (os.environ.get("SBQD_CLASH_API", "") or "").rstrip("/")
CLASH_SECRET = os.environ.get("SBQD_CLASH_SECRET", "")
PANEL_URL = os.environ.get("SBQD_PANEL_URL", "")
LANG = os.environ.get("SBQD_SUB_LANG", "zh")

FILES = {
    "links": ("links.txt", "text/plain; charset=utf-8"),
    "base64": ("links.base64", "text/plain; charset=utf-8"),
    "singbox": ("singbox.json", "application/json; charset=utf-8"),
    "mihomo": ("mihomo.yaml", "text/yaml; charset=utf-8"),
    "clash": ("mihomo.yaml", "text/yaml; charset=utf-8"),
    "qx": ("quantumultx.conf", "text/plain; charset=utf-8"),
    "quantumultx": ("quantumultx.conf", "text/plain; charset=utf-8"),
}

TITLES = {"zh": "SBQD 订阅", "en": "SBQD Subscription"}


def header_title() -> str:
    """HTTP 头只能是 latin-1；中文标题按 subconverter 约定用 base64: 前缀。"""
    title = TITLES.get(LANG, TITLES["zh"])
    if all(ord(ch) < 128 for ch in title):
        return title
    encoded = base64.b64encode(title.encode("utf-8")).decode("ascii")
    return f"base64:{encoded}"


def ua_target(user_agent: str, forced: str | None) -> str:
    if forced and forced in FILES:
        return FILES[forced][0]
    ua = (user_agent or "").lower()
    if "quantumult" in ua:
        return FILES["qx"][0]
    if any(k in ua for k in ("clash", "mihomo", "stash", "flclash", "openclash", "nikki")):
        return FILES["mihomo"][0]
    if any(k in ua for k in ("sing-box", "sfa", "sfi", "sft")):
        return FILES["singbox"][0]
    if "v2ray" in ua or "shadowrocket" in ua or "passwall" in ua or "homeproxy" in ua:
        return FILES["base64"][0]
    return FILES["base64"][0]


def read_json(name: str, default):
    try:
        return json.loads((ROOT / name).read_text(encoding="utf-8"))
    except Exception:
        return default


def clash_get(path: str):
    if not CLASH:
        return None
    headers = {"Accept": "application/json"}
    if CLASH_SECRET:
        headers["Authorization"] = f"Bearer {CLASH_SECRET}"
    req = urllib.request.Request(CLASH + path, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=2.5) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


DASHBOARD = """<!DOCTYPE html>
<html lang="__LANG__">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
  :root{--bg:#0b1020;--card:#141b2e;--line:#243049;--fg:#e8eefc;--dim:#8ea0c0;--acc:#41d1ff;--ok:#4ade80;--warn:#fbbf24}
  *{box-sizing:border-box}
  body{margin:0;background:radial-gradient(1200px 600px at 20% -10%,#1b2a4a 0,var(--bg) 55%);color:var(--fg);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;min-height:100vh}
  .wrap{max-width:860px;margin:0 auto;padding:28px 18px 48px}
  header{display:flex;align-items:center;gap:12px;margin-bottom:20px}
  .logo{width:38px;height:38px;border-radius:10px;background:linear-gradient(135deg,#41d1ff,#7c5cff);display:grid;place-items:center;font-weight:800;color:#06101f}
  h1{font-size:19px;margin:0;letter-spacing:.2px}
  .sub{color:var(--dim);font-size:12px}
  .grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
  @media(max-width:560px){.grid{grid-template-columns:1fr}}
  .card{background:linear-gradient(180deg,rgba(255,255,255,.03),rgba(255,255,255,0));border:1px solid var(--line);border-radius:14px;padding:14px 16px}
  .k{color:var(--dim);font-size:12px;letter-spacing:.4px;text-transform:uppercase}
  .v{font-size:22px;font-weight:650;margin-top:4px;font-variant-numeric:tabular-nums}
  .v.small{font-size:15px;word-break:break-all}
  .url{display:flex;gap:8px;margin-top:6px}
  input{flex:1;min-width:0;background:#0c1326;border:1px solid var(--line);color:var(--fg);border-radius:9px;padding:9px 11px;font-size:13px}
  button{background:var(--acc);border:0;color:#06101f;font-weight:700;border-radius:9px;padding:9px 14px;cursor:pointer}
  button.ghost{background:transparent;color:var(--acc);border:1px solid var(--line)}
  .row{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
  a{color:var(--acc)}
  .list{margin-top:8px}
  .item{display:flex;justify-content:space-between;gap:10px;padding:9px 0;border-bottom:1px solid var(--line);font-size:14px}
  .item:last-child{border-bottom:0}
  .tag{color:var(--dim);font-size:12px}
  .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--ok);margin-right:6px}
  .off{background:#64748b}
  footer{color:var(--dim);font-size:12px;margin-top:22px;text-align:center}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">S</div>
    <div><h1>__TITLE__</h1><div class="sub" id="gen">—</div></div>
  </header>

  <div class="card">
    <div class="k">__SUBURL__</div>
    <div class="url"><input id="suburl" readonly value="__SUBURL_VALUE__"><button id="copy">__COPY__</button></div>
    <div class="row"><a id="dashlink" href="#" target="_blank" rel="noreferrer">__SINGBOXJSON__</a>
      <a id="panel" href="__PANEL__" target="_blank" rel="noreferrer" style="__PANEL_STYLE__">__PANEL_TEXT__</a></div>
  </div>

  <div class="grid" style="margin-top:12px">
    <div class="card"><div class="k">__UPLOAD__</div><div class="v" id="up">—</div></div>
    <div class="card"><div class="k">__DOWNLOAD__</div><div class="v" id="down">—</div></div>
    <div class="card"><div class="k">__CONNECTIONS__</div><div class="v" id="conns">—</div></div>
    <div class="card"><div class="k">__MEMORY__</div><div class="v" id="mem">—</div></div>
  </div>

  <div class="card" style="margin-top:12px">
    <div class="k">__NODES__</div>
    <div class="list" id="nodes"><div class="item"><span class="tag">—</span></div></div>
  </div>

  <footer>__FOOTER__</footer>
</div>
<script>
const $ = (id) => document.getElementById(id);
const fmt = (n) => {
  if (n === null || n === undefined) return '—';
  const u = ['B','KB','MB','GB','TB']; let i = 0; let v = Number(n);
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(2)) + ' ' + u[i];
};
async function tick() {
  try {
    const r = await fetch('api/status', {cache: 'no-store'});
    const d = await r.json();
    $('gen').textContent = d.generated_at || '—';
    const t = d.traffic || {};
    $('up').textContent = fmt(t.upload);
    $('down').textContent = fmt(t.download);
    $('conns').textContent = (t.connections ?? '—');
    $('mem').textContent = fmt(d.memory);
  } catch (e) { /* keep old values */ }
  try {
    const r = await fetch('api/nodes', {cache: 'no-store'});
    const d = await r.json();
    const box = $('nodes'); box.innerHTML = '';
    (d.nodes || []).forEach(n => {
      const el = document.createElement('div'); el.className = 'item';
      const left = document.createElement('span');
      left.innerHTML = '<span class="dot ' + (n.enabled ? '' : 'off') + '"></span>' + n.name;
      const right = document.createElement('span'); right.className = 'tag';
      right.textContent = n.type + ' · ' + n.port + (n.domain ? ' · ' + n.domain : '');
      el.appendChild(left); el.appendChild(right); box.appendChild(el);
    });
    if (!(d.nodes || []).length) box.innerHTML = '<div class="item"><span class="tag">—</span></div>';
  } catch (e) { /* ignore */ }
}
$('copy').addEventListener('click', async () => {
  const el = $('suburl'); el.select();
  try { await navigator.clipboard.writeText(el.value); $('copy').textContent = '__COPIED__'; }
  catch (e) { document.execCommand('copy'); }
});
tick(); setInterval(tick, 3000);
</script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "SBQDSub/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # noqa: A003
        message = fmt % args
        if TOKEN:
            message = message.replace(TOKEN, "<token>")
        sys.stderr.write("%s - %s\n" % (self.address_string(), message))

    def _send(self, code: int, body: bytes, content_type: str, extra: dict | None = None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _not_found(self):
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def _authorized(self, token: str) -> bool:
        return bool(TOKEN) and hmac.compare_digest(token, TOKEN)

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_GET(self):  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/healthz":
            self._send(200, b"ok\n", "text/plain; charset=utf-8")
            return

        parts = [p for p in path.split("/") if p]
        if len(parts) < 2 or parts[0] != "sub":
            self._not_found()
            return

        token = parts[1]
        if not self._authorized(token):
            self._not_found()
            return

        action = parts[2] if len(parts) > 2 else ""

        if action == "":
            ua = self.headers.get("User-Agent", "")
            accept = self.headers.get("Accept", "")
            if "text/html" in accept and "mozilla" in ua.lower():
                self.send_response(302)
                self.send_header("Location", f"/sub/{token}/dashboard")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            query = parse_qs(parsed.query)
            forced = (query.get("target") or [None])[0]
            filename = ua_target(ua, forced)
            self._serve_file(filename)
            return

        if action == "dashboard":
            self._serve_dashboard(token)
            return

        if action == "api" and len(parts) > 3 and parts[3] == "status":
            self._serve_status()
            return

        if action == "api" and len(parts) > 3 and parts[3] == "nodes":
            self._serve_nodes()
            return

        if action in FILES:
            self._serve_file(FILES[action][0])
            return

        self._not_found()

    def _serve_file(self, filename: str):
        safe = os.path.basename(filename)
        target = (ROOT / safe).resolve()
        try:
            if ROOT not in target.parents and target != ROOT:
                self._not_found()
                return
            data = target.read_bytes()
        except OSError:
            self._not_found()
            return

        content_type = "text/plain; charset=utf-8"
        for _, (name, ctype) in FILES.items():
            if name == safe:
                content_type = ctype
                break

        stat = target.stat()
        etag = f'"{int(stat.st_mtime)}-{stat.st_size}"'
        if self.headers.get("If-None-Match") == etag:
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        self._send(
            200,
            data,
            content_type,
            {
                "ETag": etag,
                "Cache-Control": "no-cache",
                "profile-update-interval": "24",
                "profile-title": header_title(),
                "subscription-userinfo": "upload=0; download=0; total=0; expire=0",
            },
        )

    def _serve_dashboard(self, token: str):
        title = TITLES.get(LANG, TITLES["zh"])
        scheme = "https" if (CERT and KEY) else "http"
        host = self.headers.get("Host", "")
        sub_url = f"{scheme}://{host}/sub/{token}" if host else f"/sub/{token}"
        html = (
            DASHBOARD.replace("__LANG__", "zh" if LANG == "zh" else "en")
            .replace("__TITLE__", title)
            .replace("__SUBURL__", "订阅地址 / Subscription URL")
            .replace("__SUBURL_VALUE__", sub_url)
            .replace("__COPY__", "复制 / Copy")
            .replace("__COPIED__", "已复制")
            .replace("__SINGBOXJSON__", "sing-box JSON")
            .replace("__UPLOAD__", "上传 / Upload")
            .replace("__DOWNLOAD__", "下载 / Download")
            .replace("__CONNECTIONS__", "连接 / Connections")
            .replace("__MEMORY__", "内存 / Memory")
            .replace("__NODES__", "节点 / Nodes")
            .replace("__PANEL__", PANEL_URL or "#")
            .replace("__PANEL_STYLE__", "" if PANEL_URL else "display:none")
            .replace("__PANEL_TEXT__", "外部面板 / Panel")
            .replace("__FOOTER__", "SingBox-Quick-Deploy")
        )
        # 相对链接：sing-box JSON 直接走订阅端点
        html = html.replace('href="#" target="_blank" rel="noreferrer">sing-box JSON',
                            f'href="/sub/{token}/singbox" target="_blank" rel="noreferrer">sing-box JSON')
        self._send(
            200,
            html.encode("utf-8"),
            "text/html; charset=utf-8",
            {"Cache-Control": "no-store", "Content-Security-Policy": "default-src 'self' 'unsafe-inline'"},
        )

    def _serve_status(self):
        meta = read_json("meta.json", {})
        connections = clash_get("/connections") or {}
        memory = clash_get("/memory") or {}
        payload = {
            "generated_at": meta.get("generated_at", ""),
            "nodes": meta.get("nodes", 0),
            "memory": memory.get("inuse") if isinstance(memory, dict) else None,
            "traffic": {
                "upload": connections.get("uploadTotal") if isinstance(connections, dict) else None,
                "download": connections.get("downloadTotal") if isinstance(connections, dict) else None,
                "connections": len(connections.get("connections", [])) if isinstance(connections, dict) else None,
            },
            "panel_url": PANEL_URL,
        }
        self._send(200, json.dumps(payload).encode("utf-8"),
                   "application/json; charset=utf-8", {"Cache-Control": "no-store"})

    def _serve_nodes(self):
        data = read_json("nodes.json", {"nodes": []})
        self._send(200, json.dumps(data).encode("utf-8"),
                   "application/json; charset=utf-8", {"Cache-Control": "no-store"})


def main() -> int:
    if not TOKEN:
        sys.stderr.write("SBQD_SUB_TOKEN is required\n")
        return 2
    if not PORT:
        sys.stderr.write("SBQD_SUB_PORT is required\n")
        return 2
    if not ROOT.is_dir():
        sys.stderr.write(f"subscription root not found: {ROOT}\n")
        return 2

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True

    if CERT and KEY:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(CERT, KEY)
        server.socket = context.wrap_socket(server.socket, server_side=True)

    sys.stderr.write(f"sbqd subscription server listening on {HOST}:{PORT} tls={bool(CERT and KEY)}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
