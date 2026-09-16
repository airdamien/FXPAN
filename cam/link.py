"""Keep the two D7000s claimed: detect, live, settings, USB drop/replug."""

from __future__ import annotations

import os
import threading
import time
from contextlib import contextmanager

import dual
import settings

ROLES = ("T", "R")


class Link:
    def __init__(self, live):
        self.live = live
        self.want_live = os.environ.get("DUALS_KIOSK") == "1"
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._kick = threading.Event()
        self._th = None
        self._busy = 0
        self._have = {}
        self._assign = []
        self._msg = "usb idle"
        self._fail = 0
        self._topo = None
        self._spawn_wait = {}

    def start(self):
        if self._th and self._th.is_alive():
            return
        self._stop.clear()
        self._th = threading.Thread(target=self._loop, name="usb-link", daemon=True)
        self._th.start()

    def stop(self):
        self.want_live = False
        self._stop.set()
        self._kick.set()
        self.live.stop()

    def remember(self, assignments):
        self._assign = list(assignments or [])

    def snapshot(self):
        pair = dual.load_pair()
        live = self.live.snapshot()
        roles = {}
        with self._lock:
            have = dict(self._have)
            msg = self._msg
            busy = self._busy
        for role in ROLES:
            row = have.get(role) or {}
            info = (live.get("roles") or {}).get(role) or {}
            paired = bool(pair.get(role))
            online = bool(row.get("port"))
            roles[role] = {
                "paired": paired,
                "serial": row.get("serial") or pair.get(role) or "",
                "port": row.get("port") or "",
                "model": row.get("model") or "",
                "online": online,
                "live": bool(info.get("alive")),
                "frames": int(info.get("frames") or 0),
                "error": info.get("error") or "",
            }
        missing = [
            role for role in ROLES
            if pair.get(role) and not roles[role]["online"]
        ]
        return {
            "want_live": self.want_live,
            "busy": busy > 0,
            "running": bool(live.get("running")),
            "roles": roles,
            "missing": missing,
            "message": msg,
        }

    def have(self):
        with self._lock:
            got = dict(self._have)
        return got

    def absorb(self, rows):
        have = {}
        for row in rows or []:
            role = (row or {}).get("role")
            if role in ROLES and row.get("port"):
                have[role] = dict(row)
        if not have:
            try:
                have = dict(dual.require_online(list(rows or [])))
            except dual.CamError:
                have = {}
        with self._lock:
            self._have = have
        self._say_bus()
        return have

    def refresh(self):
        return self._scan()

    def set_live(self, on):
        self.want_live = bool(on)
        self._fail = 0
        self._kick.set()
        if not on:
            self.live.stop()

    @contextmanager
    def usb(self):
        with self._lock:
            self._busy += 1
        self.live.stop()
        time.sleep(0.35)
        try:
            yield
        finally:
            with self._lock:
                self._busy = max(0, self._busy - 1)
            self._kick.set()

    def _loop(self):
        self._boot()
        while not self._stop.is_set():
            self._kick.wait(1.2)
            self._kick.clear()
            if self._stop.is_set():
                break
            if self._busy:
                continue
            try:
                if self.want_live:
                    self._tend_live()
                else:
                    self._watch_bus()
                self._fail = 0
            except dual.CamError as exc:
                self._fail += 1
                self._msg = str(exc)
                self._stop.wait(min(8.0, 1.2 * (2 ** min(self._fail, 3))))

    def _boot(self):
        try:
            self._scan()
            if not self._assign:
                self._assign = _from_prefs()
            if self._have and self._assign:
                self._push(self._have)
            if self.want_live:
                self._start_live()
            else:
                self._say_bus()
        except dual.CamError as exc:
            self._msg = str(exc)

    def _watch_bus(self):
        ports = dual.nikon_usb_ports()
        if ports is None:
            self._scan()
        else:
            key = tuple(ports)
            changed = key != self._topo
            self._topo = key
            if changed or not self.have():
                self._scan()
            else:
                self._drop_gone(ports)
        self._say_bus()

    def _wanted(self):
        pair = dual.load_pair()
        roles = [role for role in ROLES if pair.get(role)]
        return roles or list(ROLES)

    def _scan(self):
        rows = dual.detect_bodies_cached(timeout=8)
        have = {}
        for row in rows:
            role = row.get("role")
            if role in ROLES and row.get("port"):
                have[role] = row
        if not have:
            try:
                have = dual.require_online(rows)
            except dual.CamError:
                have = {}
        with self._lock:
            before = {role: (self._have.get(role) or {}).get("serial")
                      for role in ROLES}
            self._have = have
        after = {role: (have.get(role) or {}).get("serial") for role in ROLES}
        for role in ROLES:
            if before[role] and not after[role]:
                self._msg = f"{role} USB out"
            elif after[role] and before[role] != after[role]:
                self._msg = f"{role} USB {have[role].get('port')}"
        ports = dual.nikon_usb_ports()
        if ports is not None:
            self._topo = tuple(ports)
        return have

    def _say_bus(self):
        pair = dual.load_pair()
        have = self.have()
        bits = []
        for role in ROLES:
            if have.get(role):
                bits.append(f"{role} {have[role].get('port')}")
            elif pair.get(role):
                bits.append(f"{role} out")
        self._msg = "  ".join(bits) if bits else "no cameras"

    def _push(self, have):
        if not self._assign or not have:
            return
        for role, row in have.items():
            try:
                notes = dual._set_one(row["port"], self._assign, timeout=8) or []
                if notes:
                    self._msg = f"{role} " + "; ".join(notes[:2])
            except dual.CamError as exc:
                self._msg = f"{role} set: {exc}"

    def _start_live(self):
        have = self.have()
        if not have:
            self._msg = "live: no cameras"
            return
        self.live.ensure(have)
        self._say_live()

    def _say_live(self):
        snap = self.live.snapshot()
        have = self.have()
        bits = []
        for role in ROLES:
            info = (snap.get("roles") or {}).get(role) or {}
            if have.get(role) and (info.get("alive") or info.get("frames")):
                bits.append(f"{role} {info.get('frames') or 0}f")
            elif have.get(role):
                bits.append(f"{role} wait")
            else:
                bits.append(f"{role} out")
        self._msg = "live " + "  ".join(bits)

    def _drop_gone(self, ports):
        have = self.have()
        keep = {
            role: row for role, row in have.items()
            if row.get("port") in ports
        }
        gone = [role for role in have if role not in keep]
        if not gone:
            return have
        self.live.stop_roles(gone)
        with self._lock:
            self._have = keep
        for role in gone:
            self._msg = f"{role} USB out"
        return keep

    def _claim_new(self):
        self.live.stop()
        time.sleep(0.35)
        self._scan()
        if self._have:
            self._start_live()
        else:
            self._msg = "waiting for USB"

    def _tend_live(self):
        ports = dual.nikon_usb_ports()
        if ports is not None:
            key = tuple(ports)
            have = self._drop_gone(ports)
            extra = len(ports) > len(have)
            self._topo = key
            if extra or not have:
                self._claim_new()
                return
        have = self.have()
        if not have:
            if self.live.snapshot().get("running"):
                self._say_live()
                return
            self._scan()
            if self._have:
                self._start_live()
            else:
                self._msg = "waiting for USB"
            return
        dead = self.live.dead_roles(list(have))
        if dead:
            now = time.time()
            retry = [role for role in dead if now >= self._spawn_wait.get(role, 0)]
            if retry:
                for role in retry:
                    self._spawn_wait[role] = now + 2.0
                self.live.ensure(have)
                self._msg = "live retry " + " ".join(retry)
                return
        self._say_live()


def _from_prefs():
    prefs = settings.load()
    out = []
    iso = str(prefs.get("iso") or "").strip()
    if iso.lower() == "auto":
        out.append(("isoauto", "On"))
    elif iso:
        n = iso.replace("ISO", "").replace("iso", "").strip()
        out.append(("isoauto", "Off"))
        out.append(("iso", n or iso))
    shut = str(prefs.get("shutter") or "").strip()
    if shut and shut.lower() != "auto":
        out.append(("shutterspeed", dual.format_shutter(shut)))
    for src, key in (
        ("wb", "whitebalance"),
        ("quality", "imagequality"),
        ("program", "expprogram"),
    ):
        val = str(prefs.get(src) or "").strip()
        if not val:
            continue
        if key == "expprogram" and val not in ("M", "A", "S", "P"):
            continue
        out.append((key, val))
    return out
