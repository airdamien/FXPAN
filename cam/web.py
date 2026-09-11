#!/usr/bin/env python3
"""Local control page for the two D7000s.

  python3 cam/web.py
  open http://127.0.0.1:8765
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dual

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>Nikon Duals — camera control</title>
<style>
  :root { color-scheme: dark; }
  body { font: 15px/1.45 ui-sans-serif, system-ui, sans-serif; margin: 2rem;
         background: #111; color: #e8e8e8; max-width: 52rem; }
  h1 { font-size: 1.25rem; font-weight: 600; margin: 0 0 0.25rem; }
  p.sub { color: #888; margin: 0 0 1.5rem; }
  section { border: 1px solid #333; border-radius: 8px; padding: 1rem 1.1rem; margin: 0 0 1rem; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 0.35rem 0.5rem; border-bottom: 1px solid #2a2a2a; }
  th { color: #888; font-weight: 500; }
  input { background: #1c1c1c; color: #eee; border: 1px solid #444; border-radius: 4px;
          padding: 0.35rem 0.5rem; width: 8rem; }
  button { background: #2a4a7a; color: #fff; border: 0; border-radius: 5px;
           padding: 0.45rem 0.85rem; cursor: pointer; font: inherit; }
  button.shoot { background: #8a2a2a; font-size: 1.05rem; padding: 0.7rem 1.4rem; }
  button:disabled { opacity: 0.5; cursor: wait; }
  .row { display: flex; gap: 0.6rem; flex-wrap: wrap; align-items: end; margin-top: 0.7rem; }
  label { display: flex; flex-direction: column; gap: 0.2rem; color: #aaa; font-size: 0.8rem; }
  #log { white-space: pre-wrap; color: #9c9; font: 13px ui-monospace, monospace; min-height: 3rem; }
  #log.err { color: #f88; }
</style>
<h1>Nikon Duals</h1>
<p class="sub">gphoto2 PTP · T = back (+Y) · R = side (+X) · USB fire is tens of ms apart</p>
<section>
  <table id="cams"><thead><tr>
    <th>role</th><th>serial</th><th>port</th><th>model</th>
  </tr></thead><tbody></tbody></table>
  <div class="row">
    <button id="detect">Detect</button>
    <button id="status">Status</button>
  </div>
</section>
<section>
  <div class="row">
    <label>T serial<input id="t" placeholder="back / +Y"></label>
    <label>R serial<input id="r" placeholder="side / +X"></label>
    <button id="pair">Pair</button>
  </div>
  <div class="row">
    <label>ISO<input id="iso" value="400"></label>
    <label>Shutter<input id="shutter" value="1/125"></label>
    <label>Program<input id="program" value="M"></label>
    <button id="set">Set both</button>
  </div>
  <div class="row">
    <button class="shoot" id="shoot">Shoot T + R</button>
  </div>
</section>
<pre id="log">Detect when both bodies are awake (Setup → USB → MTP/PTP).</pre>
<script>
const log = (m, err) => { const el = document.getElementById('log');
  el.textContent = m; el.className = err ? 'err' : ''; };
const api = async (path, opt) => {
  const r = await fetch(path, opt);
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
};
const fill = (rows) => {
  const tb = document.querySelector('#cams tbody');
  tb.innerHTML = '';
  (rows || []).forEach(row => {
    const tr = document.createElement('tr');
    ['role','serial','port','model'].forEach(k => {
      const td = document.createElement('td');
      td.textContent = row[k] || '—';
      tr.appendChild(td);
    });
    tb.appendChild(tr);
    if (row.role === 'T' && row.serial) document.getElementById('t').value = row.serial;
    if (row.role === 'R' && row.serial) document.getElementById('r').value = row.serial;
  });
  if (!(rows || []).length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="4">no cameras on USB</td>';
    tb.appendChild(tr);
  }
};
const bind = (id, fn) => document.getElementById(id).onclick = async () => {
  document.getElementById(id).disabled = true;
  try { await fn(); } catch (e) { log(e.message, true); }
  document.getElementById(id).disabled = false;
};
bind('detect', async () => { const j = await api('/api/detect'); fill(j.cameras); log(j.message); });
bind('status', async () => { const j = await api('/api/status'); fill(j.cameras); log(j.message); });
bind('pair', async () => {
  const j = await api('/api/pair', { method:'POST', headers:{'content-type':'application/json'},
    body: JSON.stringify({ t: t.value, r: r.value }) });
  log(j.message);
});
bind('set', async () => {
  const j = await api('/api/set', { method:'POST', headers:{'content-type':'application/json'},
    body: JSON.stringify({ iso: iso.value, shutter: shutter.value, program: program.value }) });
  log(j.message);
});
bind('shoot', async () => { const j = await api('/api/shoot', { method:'POST' }); log(j.message); });
api('/api/detect').then(j => { fill(j.cameras); log(j.message); }).catch(e => log(e.message, true));
</script>
"""


def _json(handler, code, payload):
    body = json.dumps(payload).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler):
    n = int(handler.headers.get("Content-Length") or 0)
    if n == 0:
        return {}
    return json.loads(handler.rfile.read(n))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args))

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            body = PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        try:
            if path == "/api/detect":
                rows = dual.detect_bodies()
                msg = (
                    f"{len(rows)} body(ies)"
                    if rows
                    else "no cameras. D7000 Setup → USB → MTP/PTP, wake both, plug USB."
                )
                return _json(self, 200, {"cameras": rows, "pair": dual.load_pair(), "message": msg})
            if path == "/api/status":
                rows = dual.detect_bodies()
                if not rows:
                    raise dual.CamError("no cameras")
                from concurrent.futures import ThreadPoolExecutor

                with ThreadPoolExecutor(max_workers=len(rows)) as pool:
                    blocks = list(pool.map(dual._status_one, rows))
                lines = []
                for b in blocks:
                    lines.append(
                        f"{b.get('role')}  iso={b.get('iso')}  "
                        f"shutter={b.get('shutterspeed')}  {b.get('port')}"
                    )
                return _json(self, 200, {"cameras": rows, "status": blocks, "message": "\n".join(lines)})
        except dual.CamError as exc:
            return _json(self, 400, {"error": str(exc)})
        return _json(self, 404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = _read_json(self)
            if path == "/api/pair":
                t, r = (data.get("t") or "").strip(), (data.get("r") or "").strip()
                if not t or not r:
                    raise dual.CamError("need T and R serials")
                dual.save_pair(t, r)
                return _json(self, 200, {"message": f"paired T={t}  R={r}"})
            if path == "/api/set":
                assignments = []
                if data.get("iso"):
                    assignments.append(("iso", data["iso"]))
                if data.get("shutter"):
                    assignments.append(("shutterspeed", data["shutter"]))
                if data.get("program"):
                    assignments.append(("expprogram", data["program"]))
                if not assignments:
                    raise dual.CamError("nothing to set")
                have = dual.require_paired(dual.detect_bodies())
                from concurrent.futures import ThreadPoolExecutor

                with ThreadPoolExecutor(max_workers=2) as pool:
                    for role in ("T", "R"):
                        pool.submit(dual._set_one, have[role]["port"], assignments).result()
                return _json(
                    self, 200,
                    {"message": "set " + " ".join(f"{k}={v}" for k, v in assignments)},
                )
            if path == "/api/shoot":
                from concurrent.futures import ThreadPoolExecutor
                from datetime import datetime

                have = dual.require_paired(dual.detect_bodies())
                dest = Path("captures")
                stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                with ThreadPoolExecutor(max_workers=2) as pool:
                    futs = [
                        pool.submit(dual._shoot_one, role, have[role]["port"], dest, stamp)
                        for role in ("T", "R")
                    ]
                    times = [fut.result() for fut in futs]
                msg = "  ".join(f"{role} {dt:.2f}s" for role, dt in times)
                return _json(self, 200, {"message": f"shot {stamp}  {msg}  → captures/"})
        except dual.CamError as exc:
            return _json(self, 400, {"error": str(exc)})
        return _json(self, 404, {"error": "not found"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"http://127.0.0.1:{port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
