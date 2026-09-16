"""Pi Wi-Fi via NetworkManager. Scan, join, AP for a phone on the kiosk."""

from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
import threading
import time
from pathlib import Path

import dual

PATH = Path(__file__).resolve().parent / "wifi.json"
AP_SSID = "D12600"
AP_CON = "D12600-AP"
ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"
WATCH_INTERVAL_S = 75
WATCH_PING_FAILS = 2
WATCH_MIN_SIGNAL = 35
WATCH_RECONNECT_COOLDOWN_S = 120
WATCH_SAVED_MAX = 8


def _fields(line):
    out, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def parse_networks(raw):
    best = {}
    for line in (raw or "").splitlines():
        parts = _fields(line)
        if len(parts) < 4:
            continue
        in_use, ssid, signal, security = parts[0], parts[1], parts[2], parts[3]
        if not ssid:
            continue
        try:
            sig = int(signal)
        except ValueError:
            sig = 0
        row = {
            "ssid": ssid,
            "signal": sig,
            "security": security.replace(" ", "/").strip() or "",
            "in_use": in_use == "*",
        }
        prev = best.get(ssid)
        if prev is None or row["signal"] > prev["signal"] or row["in_use"]:
            if prev and prev["in_use"] and not row["in_use"]:
                continue
            best[ssid] = row
    rows = list(best.values())
    rows.sort(key=lambda r: (not r["in_use"], -r["signal"], r["ssid"].lower()))
    return rows


def _nmcli(args, timeout=25):
    if not shutil.which("nmcli"):
        raise dual.CamError("nmcli not found — Wi-Fi is on the Pi")
    try:
        env = os.environ.copy()
        env["LC_ALL"] = "C"
        proc = subprocess.run(
            ["nmcli", "-t", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired as exc:
        raise dual.CamError("wifi timed out") from exc
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "nmcli failed").strip().splitlines()
        raise dual.CamError(err[-1] if err else "nmcli failed")
    return proc.stdout


def _norm_saved(saved):
    rows = []
    seen = set()
    for item in saved or []:
        if not isinstance(item, dict):
            continue
        ssid = str(item.get("ssid") or "").strip()
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        rows.append({"ssid": ssid, "psk": str(item.get("psk") or "")})
    return rows


def _load_creds():
    out = {"ap_ssid": AP_SSID, "ap_psk": "", "saved": []}
    if not PATH.is_file():
        return out
    try:
        data = json.loads(PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return out
    if not isinstance(data, dict):
        return out
    ssid = str(data.get("ap_ssid") or "").strip() or AP_SSID
    psk = str(data.get("ap_psk") or "").strip()
    out["ap_ssid"] = ssid
    out["ap_psk"] = psk
    out["saved"] = _norm_saved(data.get("saved"))
    return out


def _save_creds(creds):
    row = {
        "ap_ssid": creds.get("ap_ssid") or AP_SSID,
        "ap_psk": creds.get("ap_psk") or "",
        "saved": _norm_saved(creds.get("saved")),
    }
    PATH.write_text(json.dumps(row) + "\n")
    return row


def remember_network(ssid, psk=""):
    ssid = (ssid or "").strip()
    if not ssid:
        return
    creds = _load_creds()
    saved = [r for r in creds["saved"] if r["ssid"] != ssid]
    saved.insert(0, {"ssid": ssid, "psk": str(psk or "")})
    creds["saved"] = saved[:WATCH_SAVED_MAX]
    _save_creds(creds)


def _creds():
    creds = _load_creds()
    if len(creds["ap_psk"]) >= 8:
        return creds
    creds["ap_psk"] = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return _save_creds(creds)


def _wifi_device():
    for line in _nmcli(["-f", "DEVICE,TYPE,STATE", "device", "status"]).splitlines():
        parts = _fields(line)
        if len(parts) >= 2 and parts[1] == "wifi":
            return parts[0]
    return ""


def _ip4(device):
    if not device:
        return ""
    try:
        raw = _nmcli(["-f", "IP4.ADDRESS", "device", "show", device], timeout=8)
    except dual.CamError:
        return ""
    for line in raw.splitlines():
        if ":" not in line:
            continue
        addr = line.split(":", 1)[1].strip().split("/", 1)[0]
        if addr and not addr.startswith("127."):
            return addr
    return ""


def _active_wifi():
    try:
        raw = _nmcli(["-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"], timeout=8)
    except dual.CamError:
        return "", "", ""
    for line in raw.splitlines():
        parts = _fields(line)
        if len(parts) >= 3 and parts[1] == "wifi":
            return parts[0], parts[2], parts[1]
    return "", "", ""


def _con_mode(name):
    if not name:
        return ""
    try:
        raw = _nmcli(["-g", "802-11-wireless.mode", "connection", "show", name], timeout=8)
    except dual.CamError:
        return ""
    return raw.strip()


def _url(ip, port=8787):
    return f"http://{ip}:{port}/" if ip else ""


def _default_gateway():
    if not shutil.which("ip"):
        return ""
    try:
        proc = subprocess.run(
            ["ip", "-4", "route", "show", "default"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    for line in (proc.stdout or "").splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "default" and parts[1] == "via":
            return parts[2]
    return ""


def _ping(host, timeout_s=2):
    if not host or not shutil.which("ping"):
        return False
    wait = str(max(1, int(timeout_s)))
    try:
        proc = subprocess.run(
            ["ping", "-c", "1", "-W", wait, host],
            capture_output=True,
            timeout=timeout_s + 3,
            check=False,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _near_saved(nets, saved, min_signal=WATCH_MIN_SIGNAL):
    known = {r["ssid"]: r for r in _norm_saved(saved)}
    rows = []
    for net in nets:
        cred = known.get(net["ssid"])
        if cred and net["signal"] >= min_signal:
            rows.append((net, cred))
    rows.sort(key=lambda item: -item[0]["signal"])
    return rows


def _connection_for_ssid(ssid):
    try:
        names = [
            line.strip()
            for line in _nmcli(["-f", "NAME", "connection", "show"], timeout=8).splitlines()
        ]
    except dual.CamError:
        return ""
    for name in names:
        if not name or name == AP_CON:
            continue
        try:
            got = _nmcli(
                ["-g", "802-11-wireless.ssid", "connection", "show", name],
                timeout=8,
            ).strip()
        except dual.CamError:
            continue
        if got == ssid:
            return name
    return ""


def _reconnect_station(ssid, psk=""):
    name = _connection_for_ssid(ssid)
    if name:
        try:
            _nmcli(["connection", "up", name], timeout=25)
            dev = _wifi_device()
            _powersave_off(dev, name)
            return
        except dual.CamError:
            pass
    args = ["device", "wifi", "connect", ssid]
    if psk:
        args.extend(["password", psk])
    _nmcli(args, timeout=35)
    name, dev, _typ = _active_wifi()
    _powersave_off(dev or _wifi_device(), name)


def _powersave_off(device, con=""):
    if device:
        try:
            subprocess.run(
                ["iw", "dev", device, "set", "power_save", "off"],
                capture_output=True, timeout=5, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    if con:
        try:
            _nmcli(["connection", "modify", con, "802-11-wireless.powersave", "2"],
                   timeout=8)
        except dual.CamError:
            pass


def _attach_watch(row):
    snap = WATCH.snapshot()
    if snap.get("running"):
        row["watch"] = snap
    return row


def status(networks=None):
    creds = _load_creds()
    out = {
        "available": False,
        "mode": "off",
        "ssid": "",
        "ip": "",
        "device": "",
        "signal": None,
        "security": "",
        "ap_ssid": creds["ap_ssid"],
        "ap_psk": creds["ap_psk"],
        "url": "",
        "networks": networks if networks is not None else [],
        "message": "nmcli not found — Wi-Fi is on the Pi",
    }
    try:
        device = _wifi_device()
    except dual.CamError as exc:
        out["message"] = str(exc)
        return _attach_watch(out)
    creds = _creds()
    out["available"] = True
    out["ap_ssid"] = creds["ap_ssid"]
    out["ap_psk"] = creds["ap_psk"]
    out["device"] = device
    name, dev, _typ = _active_wifi()
    if dev:
        out["device"] = dev
    ip = _ip4(out["device"])
    out["ip"] = ip
    out["url"] = _url(ip)
    mode = _con_mode(name)
    if mode == "ap" or name == AP_CON:
        out["mode"] = "ap"
        out["ssid"] = out["ap_ssid"]
        out["message"] = f"AP {out['ap_ssid']}  {out['url'] or 'no ip'}"
        return _attach_watch(out)
    if networks is not None:
        out["networks"] = networks
        used = next((n for n in networks if n["in_use"]), None)
        if used:
            out["mode"] = "station"
            out["ssid"] = used["ssid"]
            out["signal"] = used["signal"]
            out["security"] = used["security"]
            out["message"] = f"{used['ssid']}  {out['url'] or 'no ip'}"
            return _attach_watch(out)
    if name:
        out["mode"] = "station"
        out["ssid"] = name
        out["message"] = f"{name}  {out['url'] or 'no ip'}"
        return _attach_watch(out)
    out["message"] = "wifi idle — scan or start AP"
    return _attach_watch(out)


def scan():
    _nmcli(["radio", "wifi", "on"], timeout=8)
    nets = parse_networks(
        _nmcli(
            ["-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
             "--rescan", "yes"],
            timeout=30,
        )
    )
    out = status(nets)
    out["networks"] = nets
    out["message"] = f"{len(nets)} network(s)"
    return out


def join(ssid, psk=""):
    ssid = (ssid or "").strip()
    if not ssid:
        raise dual.CamError("need an SSID")
    _nmcli(["radio", "wifi", "on"], timeout=8)
    args = ["device", "wifi", "connect", ssid]
    if psk:
        args.extend(["password", psk])
    _nmcli(args, timeout=35)
    name, dev, _typ = _active_wifi()
    _powersave_off(dev or _wifi_device(), name)
    remember_network(ssid, psk)
    out = status()
    out["message"] = f"joined {ssid}  {out['url'] or ''}".strip()
    return out


def set_ap(on):
    on = bool(on)
    device = _wifi_device()
    if not device:
        raise dual.CamError("no wifi radio")
    if not on:
        try:
            _nmcli(["connection", "down", AP_CON], timeout=15)
        except dual.CamError:
            pass
        out = status()
        out["message"] = "AP off"
        return out
    creds = _creds()
    try:
        names = [
            line.strip()
            for line in _nmcli(["-f", "NAME", "connection", "show"], timeout=8).splitlines()
        ]
        if AP_CON not in names:
            _nmcli(
                ["connection", "add", "type", "wifi", "ifname", device,
                 "con-name", AP_CON, "autoconnect", "no", "ssid", creds["ap_ssid"]],
                timeout=12,
            )
        _nmcli(
            ["connection", "modify", AP_CON,
             "802-11-wireless.mode", "ap",
             "802-11-wireless.band", "bg",
             "ipv4.method", "shared",
             "wifi-sec.key-mgmt", "wpa-psk",
             "wifi-sec.psk", creds["ap_psk"]],
            timeout=12,
        )
        _nmcli(["connection", "up", AP_CON], timeout=25)
        _powersave_off(device, AP_CON)
    except dual.CamError:
        _nmcli(
            ["device", "wifi", "hotspot", "ifname", device,
             "con-name", AP_CON, "ssid", creds["ap_ssid"],
             "password", creds["ap_psk"]],
            timeout=30,
        )
        _powersave_off(device, AP_CON)
    out = status()
    out["ap_ssid"] = creds["ap_ssid"]
    out["ap_psk"] = creds["ap_psk"]
    out["mode"] = "ap"
    out["ssid"] = creds["ap_ssid"]
    out["message"] = f"AP {creds['ap_ssid']}  {out['url'] or 'wait for ip'}"
    return out


class Watch:
    """Background station health check: ping gateway, rejoin saved SSIDs."""

    def __init__(self, interval_s=WATCH_INTERVAL_S):
        self._interval = interval_s
        self._stop = threading.Event()
        self._th = None
        self._lock = threading.Lock()
        self._busy = False
        self._failures = 0
        self._last_ping = None
        self._last_check = 0.0
        self._last_reconnect = 0.0
        self._msg = "watch idle"
        self._gw = ""

    def start(self):
        if self._th and self._th.is_alive():
            return
        if not shutil.which("nmcli"):
            return
        self._stop.clear()
        self._th = threading.Thread(target=self._loop, name="wifi-watch", daemon=True)
        self._th.start()

    def stop(self):
        self._stop.set()

    def snapshot(self):
        with self._lock:
            return {
                "running": bool(self._th and self._th.is_alive()),
                "message": self._msg,
                "failures": self._failures,
                "last_ping": self._last_ping,
                "gateway": self._gw,
                "busy": self._busy,
                "last_check": self._last_check,
            }

    def _set_msg(self, msg):
        with self._lock:
            self._msg = msg

    def _loop(self):
        while not self._stop.wait(self._interval):
            try:
                self._tick()
            except Exception as exc:
                self._set_msg(f"watch error: {exc}")

    def _tick(self):
        with self._lock:
            if self._busy:
                return
            self._busy = True
        try:
            self._run_tick()
        finally:
            with self._lock:
                self._busy = False
                self._last_check = time.time()

    def _run_tick(self):
        try:
            st = status()
        except Exception as exc:
            self._set_msg(f"watch status failed: {exc}")
            return

        if not st.get("available"):
            self._set_msg("watch off (no nmcli)")
            return

        if st.get("mode") == "ap":
            with self._lock:
                self._failures = 0
                self._last_ping = None
                self._gw = ""
            self._set_msg("watch idle (AP mode)")
            return

        saved = _load_creds().get("saved") or []
        if not saved:
            self._set_msg("watch idle (no saved networks)")
            return

        try:
            nets = parse_networks(
                _nmcli(
                    ["-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"],
                    timeout=15,
                )
            )
        except dual.CamError as exc:
            self._set_msg(f"watch list failed: {exc}")
            return

        near = _near_saved(nets, saved)
        mode = st.get("mode")
        ssid = st.get("ssid") or ""
        ip = st.get("ip") or ""

        if mode == "station" and ssid:
            gw = _default_gateway()
            with self._lock:
                self._gw = gw
            ping_ok = _ping(gw) if gw else False
            link_ok = bool(ip) and (ping_ok or not gw)
            if link_ok:
                with self._lock:
                    self._failures = 0
                    self._last_ping = True
                self._set_msg(f"watch ok {ssid} gw={gw or 'n/a'}")
                return
            with self._lock:
                self._failures += 1
                self._last_ping = False
                fails = self._failures
            self._set_msg(
                f"watch degraded {ssid} ({fails}/{WATCH_PING_FAILS}) gw={gw or 'n/a'}"
            )
            if fails >= WATCH_PING_FAILS:
                self._try_reconnect(saved, prefer=ssid, near=near)
            return

        if near:
            net, _cred = near[0]
            self._set_msg(f"watch {net['ssid']} nearby ({net['signal']}%) — reconnecting")
            self._try_reconnect(saved, prefer=net["ssid"], near=near)
            return

        with self._lock:
            self._failures = 0
        self._set_msg("watch idle (no saved SSID in range)")

    def _try_reconnect(self, saved, prefer="", near=None):
        now = time.time()
        with self._lock:
            if now - self._last_reconnect < WATCH_RECONNECT_COOLDOWN_S:
                self._set_msg("watch reconnect skipped (cooldown)")
                return
            self._last_reconnect = now
            self._failures = 0

        creds_by_ssid = {r["ssid"]: r for r in saved}
        targets = []
        if prefer and prefer in creds_by_ssid:
            targets.append(prefer)
        for net, _cred in near or []:
            if net["ssid"] not in targets:
                targets.append(net["ssid"])

        for ssid in targets:
            row = creds_by_ssid.get(ssid)
            if not row:
                continue
            try:
                _reconnect_station(ssid, row.get("psk") or "")
            except dual.CamError as exc:
                self._set_msg(f"watch reconnect {ssid} failed: {exc}")
                continue
            st = status()
            if st.get("mode") != "station":
                continue
            gw = _default_gateway()
            with self._lock:
                self._gw = gw
            if st.get("ip") and (not gw or _ping(gw)):
                self._set_msg(f"watch rejoined {ssid}")
                return
            if st.get("ip"):
                self._set_msg(f"watch rejoined {ssid} (no gw ping)")
                return
        self._set_msg("watch reconnect failed")


WATCH = Watch()
