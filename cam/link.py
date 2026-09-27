"""Keep the two D7000s claimed: detect, live, settings, USB drop/replug."""

from __future__ import annotations

import threading
import time
from contextlib import contextmanager

import dual
import settings

ROLES = ("T", "R")


class Link:
    def __init__(self, live):
        self.live = live
        self.want_live = False
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
        self._hud = {}
        self._fail_n = {}
        self._probe_at = 0.0
        self._extras = []
        self._gone_since = {}
        self._hud_at = 0.0
        self._idle = False

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

    def set_hud(self, blocks):
        pair = dual.load_pair()
        serial_role = {serial: role for role, serial in pair.items()}
        hud = {}
        for block in blocks or []:
            role = block.get("role")
            if role not in ROLES:
                sn = (block.get("serial") or block.get("serialnumber") or "").strip()
                role = serial_role.get(sn, "")
            if role not in ROLES:
                continue
            row = dict(block)
            row["role"] = role
            hud[role] = row
        with self._lock:
            self._hud.update(hud)

    def snapshot(self):
        pair = dual.load_pair()
        live = self.live.snapshot()
        roles = {}
        with self._lock:
            have = dict(self._have)
            msg = self._msg
            busy = self._busy
            hud = {role: dict(row) for role, row in self._hud.items()}
            extras = [dict(row) for row in self._extras]
        speeds = dual.nikon_usb_info() or {}
        for role in ROLES:
            row = have.get(role) or {}
            info = (live.get("roles") or {}).get(role) or {}
            paired = bool(pair.get(role))
            online = bool(row.get("port"))
            port = row.get("port") or ""
            link = (speeds.get(port) or {}).get("speed") or row.get("usb_speed") or ""
            roles[role] = {
                "paired": paired,
                "serial": row.get("serial") or pair.get(role) or "",
                "port": port,
                "model": row.get("model") or "",
                "usb_speed": link,
                "online": online,
                "live": bool(info.get("alive")),
                "frames": int(info.get("frames") or 0),
                "error": info.get("error") or "",
            }
        extras = [
            dict(row, usb_speed=(speeds.get(row.get("port") or "") or {}).get("speed")
                 or row.get("usb_speed") or "")
            for row in extras
        ]
        missing = [
            role for role in ROLES
            if pair.get(role) and not roles[role]["online"]
        ]
        return {
            "want_live": self.want_live,
            "busy": busy > 0,
            "running": bool(live.get("running")),
            "roles": roles,
            "extras": extras,
            "missing": missing,
            "message": msg,
            "status": hud,
            "idle": self._idle,
        }

    def have(self):
        with self._lock:
            got = dict(self._have)
        return got

    def absorb(self, rows):
        rows = list(rows or [])
        dual.seat_open_roles(rows, persist=True)
        have = {}
        extras = []
        for row in rows:
            role = (row or {}).get("role")
            if role in ROLES and row.get("port"):
                have[role] = dict(row)
            elif (row or {}).get("port"):
                extras.append(dict(row))
        if not have:
            try:
                have = dict(dual.require_online(list(rows or [])))
            except dual.CamError:
                have = {}
        with self._lock:
            self._have = have
            self._extras = extras
        self._fail_n = {}
        self._say_bus()
        return have

    def rebind(self):
        """Re-read USB and map T/R from cameras.json serials."""
        rows = dual.detect_bodies()
        return self.absorb(rows)

    def refresh(self):
        return self._scan()

    def set_live(self, on):
        was = self.want_live
        self.want_live = bool(on)
        if on:
            self._idle = False
        self._fail = 0
        self._fail_n = {}
        self._kick.set()
        if on:
            return
        self.live.stop()
        if was:
            self._refresh_hud()

    def set_idle(self, on):
        self._idle = bool(on)
        if self._idle:
            self.want_live = False
            self.live.stop()
        self._kick.set()

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
            self._fail_n = {}
            self._kick.set()

    @contextmanager
    def gpio_window(self, settle=1.0):
        """Drop gphoto2 USB so the 10-pin remote can fire."""
        self.live.stop()
        dual.free_usb()
        time.sleep(0.35)
        with self._lock:
            self._busy += 1
        try:
            yield
        finally:
            time.sleep(settle)
            with self._lock:
                self._busy = max(0, self._busy - 1)
            self._fail_n = {}
            self._kick.set()

    def _loop(self):
        self._boot()
        while not self._stop.is_set():
            self._kick.wait(8.0 if self._idle else 1.2)
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
            if self._have:
                try:
                    info = dual.sync_clocks(self._have)
                    if info.get("message"):
                        self._msg = info["message"]
                except dual.CamError:
                    pass
            if self.want_live:
                self._start_live()
            else:
                self._refresh_hud()
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
            if not self.have():
                self._scan()
            elif changed:
                # A PTP session makes a D800 re-enumerate. The devnum changes
                # and the body is still the only Nikon on the bus — reading
                # the serial again just to notice that flashes the LCD.
                self._retarget(ports)
            else:
                self._drop_gone(ports)
        self._say_bus()
        if time.time() - self._hud_at > (120 if self._idle else 20):
            self._refresh_hud()

    def _wanted(self):
        pair = dual.load_pair()
        roles = [role for role in ROLES if pair.get(role)]
        return roles or list(ROLES)

    def _scan(self):
        rows = dual.detect_bodies_cached(timeout=8)
        dual.seat_open_roles(rows, persist=True)
        have = {}
        extras = []
        for row in rows:
            role = row.get("role")
            if role in ROLES and row.get("port"):
                have[role] = row
            elif row.get("port"):
                extras.append(dict(row))
        if not have:
            try:
                have = dual.require_online(rows)
            except dual.CamError:
                have = {}
        with self._lock:
            before = {role: (self._have.get(role) or {}).get("serial")
                      for role in ROLES}
            self._have = have
            self._extras = extras
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

    def _retarget(self, ports):
        have = self.have()
        online = {role: row for role, row in have.items() if row.get("port")}
        moved = [port for port in ports if port not in {row.get("port") for row in online.values()}]
        stale = [role for role, row in online.items() if row.get("port") not in ports]
        if len(moved) != 1 or len(stale) != 1 or len(ports) != len(online):
            self._scan()
            return
        role = stale[0]
        row = dict(online[role])
        row["port"] = moved[0]
        updated = dict(have)
        updated[role] = row
        with self._lock:
            self._have = updated
        self._msg = f"{role} USB {moved[0]}"

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

    def _claim_ports(self, ports):
        """Identify extra Nikon ports by serial. Do not stop a healthy live stream."""
        added = {}
        for port in ports:
            try:
                row = dual.probe_port(port, timeout=6)
            except dual.CamError:
                continue
            role = row.get("role")
            if role not in ROLES or not row.get("serial"):
                continue
            added[role] = row
        if not added:
            extras = []
            for port in ports:
                try:
                    row = dual.probe_port(port, timeout=6)
                except dual.CamError:
                    continue
                if row.get("port") and row.get("role") not in ROLES:
                    extras.append(row)
            if extras:
                with self._lock:
                    self._extras = extras
            return {}
        with self._lock:
            have = dict(self._have)
            have.update(added)
            self._have = have
        for role in added:
            self._fail_n.pop(role, None)
        added_ports = {row.get("port") for row in added.values()}
        with self._lock:
            self._extras = [
                row for row in self._extras if row.get("port") not in added_ports
            ]
        self.live.ensure(self.have(), only=list(added))
        self._say_live()
        return added

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
            have = self._drop_gone(ports)
            extra = dual.orphan_ports(ports, have)
            self._topo = tuple(ports)
            if extra:
                now = time.time()
                if now >= self._probe_at:
                    self._probe_at = now + 5.0
                    self._claim_ports(extra)
                have = self.have()
            if not have:
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
        snap = self.live.snapshot()
        for role, info in (snap.get("roles") or {}).items():
            if info.get("frames"):
                self._fail_n[role] = 0
        dead = self.live.dead_roles(list(have))
        if dead:
            now = time.time()
            retry = []
            held = []
            for role in dead:
                n = self._fail_n.get(role, 0)
                if n >= 8:
                    held.append(role)
                    continue
                if now < self._spawn_wait.get(role, 0):
                    continue
                retry.append(role)
            if held and not retry:
                self._msg = "live " + " ".join(
                    f"{role} gave up" for role in held
                ) + "  — Detect to retry"
                return
            if retry:
                for role in retry:
                    n = self._fail_n.get(role, 0)
                    self._fail_n[role] = n + 1
                    self._spawn_wait[role] = now + retry_wait(n)
                self.live.stop_roles(retry)
                time.sleep(0.45)
                self.live.ensure(have, only=retry)
                self._msg = "live retry " + " ".join(retry)
                return
        self._say_live()


    def _refresh_hud(self, have=None):
        """Read ISO/battery/etc while PTP is free. Live view owns the bus."""
        if self.live.snapshot().get("running"):
            return
        have = have or self.have()
        rows = [row for row in have.values() if (row or {}).get("port")]
        if not rows:
            return
        from concurrent.futures import ThreadPoolExecutor
        try:
            with ThreadPoolExecutor(max_workers=len(rows)) as pool:
                blocks = list(pool.map(dual._status_one, rows))
        except dual.CamError:
            return
        if blocks:
            self.set_hud(blocks)
            self._hud_at = time.time()

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
        self._refresh_hud(have)
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
        now = time.time()
        keep = {}
        drop = []
        for role, row in have.items():
            if row.get("port") in ports:
                self._gone_since.pop(role, None)
                keep[role] = row
                continue
            started = self._gone_since.setdefault(role, now)
            if now - started < 2.5:
                keep[role] = row
            else:
                drop.append(role)
        if drop:
            self.live.stop_roles(drop)
            for role in drop:
                self._gone_since.pop(role, None)
                self._msg = f"{role} USB out"
        with self._lock:
            self._have = keep
        return keep


def retry_wait(fails):
    return min(30.0, 3.0 * (2 ** min(max(int(fails), 0), 4)))


def _from_prefs():
    prefs = settings.load()
    if prefs.get("follow_cam"):
        return []
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
