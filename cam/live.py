#!/usr/bin/env python3
"""D7000 live view: gphoto2 --capture-movie --stdout.

Low-res JPEG preview (typically ~640px, a few fps). Holds the USB port
for each body; stop before detect / set / shoot.
"""

from __future__ import annotations

import signal
import subprocess
import threading
import time

import dual

SOI = b"\xff\xd8"
EOI = b"\xff\xd9"
FIRST_S = 18.0
STALE_S = 6.0
SPAWN_GAP_S = 0.7


def split_jpegs(buf):
    frames = []
    while True:
        start = buf.find(SOI)
        if start < 0:
            return frames, b""
        if start:
            buf = buf[start:]
        end = buf.find(EOI, 2)
        if end < 0:
            return frames, buf
        frames.append(buf[: end + 2])
        buf = buf[end + 2 :]


def paired_on_usb():
    try:
        rows = dual.detect_bodies_cached(timeout=8)
    except dual.CamError:
        return {}
    if not rows:
        return {}
    return dual.require_online(rows)


class Live:
    def __init__(self):
        self._lock = threading.Lock()
        self._procs = {}
        self._frames = {}
        self._n = {}
        self._err = {}
        self._ports = {}
        self._born = {}
        self._seen = {}

    def running(self):
        with self._lock:
            return {role: proc.poll() is None for role, proc in self._procs.items()}

    def snapshot(self):
        with self._lock:
            roles = {}
            for role, proc in self._procs.items():
                roles[role] = {
                    "frames": self._n.get(role, 0),
                    "error": self._err.get(role, ""),
                    "port": self._ports.get(role, ""),
                    "alive": proc.poll() is None,
                }
            return {
                "running": any(info["alive"] for info in roles.values()),
                "roles": roles,
            }

    def jpeg(self, role):
        with self._lock:
            return self._frames.get(role)

    def start_have(self, have):
        self.stop()
        return self.ensure(have)

    def ensure(self, have, only=None):
        """Spawn missing/dead roles. Leave healthy capture-movie processes up."""
        have = {
            role: dict(row)
            for role, row in dict(have or {}).items()
            if (row or {}).get("port")
        }
        wanted = set(have)
        if only is not None:
            wanted &= set(only)
        with self._lock:
            extra = [role for role in self._procs if role not in have]
        if extra:
            self.stop_roles(extra)
        spawned = 0
        for role, row in have.items():
            if role not in wanted:
                continue
            port = row["port"]
            with self._lock:
                proc = self._procs.get(role)
                same = (
                    proc is not None
                    and proc.poll() is None
                    and self._ports.get(role) == port
                )
            if same:
                continue
            self.stop_roles([role])
            if spawned:
                time.sleep(SPAWN_GAP_S)
            self._spawn(role, port)
            spawned += 1
        if not spawned:
            return have
        deadline = time.time() + 1.6
        while time.time() < deadline:
            snap = self.snapshot()
            if any(info["alive"] or info["frames"] for info in snap["roles"].values()):
                return have
            time.sleep(0.08)
        return have

    def start_from_usb(self):
        have = paired_on_usb()
        return self.start_have(have)

    def dead_roles(self, wanted):
        now = time.time()
        with self._lock:
            out = []
            for role in wanted:
                proc = self._procs.get(role)
                if proc is None or proc.poll() is not None:
                    out.append(role)
                    continue
                n = self._n.get(role, 0)
                born = self._born.get(role, now)
                seen = self._seen.get(role, 0)
                if n == 0 and now - born > FIRST_S:
                    out.append(role)
                elif n and now - seen > STALE_S:
                    out.append(role)
            return out

    def stop(self):
        with self._lock:
            roles = list(self._procs)
        self.stop_roles(roles)

    def stop_roles(self, roles):
        roles = list(roles or [])
        with self._lock:
            procs = []
            for role in roles:
                proc = self._procs.pop(role, None)
                if proc is not None:
                    procs.append(proc)
                self._ports.pop(role, None)
                self._frames.pop(role, None)
                self._n.pop(role, None)
                self._err.pop(role, None)
                self._born.pop(role, None)
                self._seen.pop(role, None)
        for proc in procs:
            if proc.poll() is None:
                proc.send_signal(signal.SIGINT)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)

    def _spawn(self, role, port):
        try:
            proc = subprocess.Popen(
                [dual.GPHOTO2, "--port", port, "--capture-movie", "--stdout"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0,
            )
        except FileNotFoundError as exc:
            raise dual.CamError(f"gphoto2 not found: {dual.GPHOTO2}") from exc
        with self._lock:
            self._procs[role] = proc
            self._ports[role] = port
            self._n[role] = 0
            self._err[role] = ""
            self._born[role] = time.time()
            self._seen[role] = 0
            self._frames.pop(role, None)
        threading.Thread(target=self._read, args=(role, proc), daemon=True).start()
        threading.Thread(target=self._stderr, args=(role, proc), daemon=True).start()

    def _read(self, role, proc):
        buf = b""
        while True:
            chunk = proc.stdout.read(16384)
            if not chunk:
                break
            frames, buf = split_jpegs(buf + chunk)
            if not frames:
                continue
            with self._lock:
                self._frames[role] = frames[-1]
                self._n[role] = self._n.get(role, 0) + len(frames)
                self._seen[role] = time.time()

    def _stderr(self, role, proc):
        text = proc.stderr.read()
        if not text:
            return
        with self._lock:
            self._err[role] = text.decode("utf-8", "replace").strip()[-500:]
