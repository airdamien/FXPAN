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
    return dual.require_online(dual.detect_bodies())


class Live:
    def __init__(self):
        self._lock = threading.Lock()
        self._procs = {}
        self._frames = {}
        self._n = {}
        self._err = {}
        self._ports = {}

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

    def start_from_usb(self):
        self.stop()
        have = paired_on_usb()
        dual.free_usb()
        for role, row in have.items():
            self._spawn(role, row["port"])
        deadline = time.time() + 1.2
        while time.time() < deadline:
            snap = self.snapshot()
            if snap["running"] or any(info["frames"] for info in snap["roles"].values()):
                break
            if snap["roles"] and not any(info["alive"] for info in snap["roles"].values()):
                break
            time.sleep(0.1)
        snap = self.snapshot()
        if snap["roles"] and not snap["running"]:
            bits = [
                f"{role}: {info['error'] or 'gphoto2 exited'}"
                for role, info in snap["roles"].items()
            ]
            raise dual.CamError("live view failed. " + "  ".join(bits))
        return have

    def stop(self):
        with self._lock:
            procs = list(self._procs.items())
            self._procs = {}
        for _role, proc in procs:
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
            )
        except FileNotFoundError as exc:
            raise dual.CamError(f"gphoto2 not found: {dual.GPHOTO2}") from exc
        with self._lock:
            self._procs[role] = proc
            self._ports[role] = port
            self._n[role] = 0
            self._err[role] = ""
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

    def _stderr(self, role, proc):
        text = proc.stderr.read()
        if not text:
            return
        with self._lock:
            self._err[role] = text.decode("utf-8", "replace").strip()[-500:]
