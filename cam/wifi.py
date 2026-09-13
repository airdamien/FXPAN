"""Pi Wi-Fi via NetworkManager. Scan, join, AP for a phone on the kiosk."""

from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import dual

PATH = Path(__file__).resolve().parent / "wifi.json"
AP_SSID = "D12600"
AP_CON = "D12600-AP"
ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"


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


def _load_creds():
    out = {"ap_ssid": AP_SSID, "ap_psk": ""}
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
    return {"ap_ssid": ssid, "ap_psk": psk}


def _save_creds(creds):
    PATH.write_text(json.dumps(creds) + "\n")
    return creds


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
        return out
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
        return out
    if networks is None:
        try:
            networks = parse_networks(
                _nmcli(["-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                        "--rescan", "no"], timeout=12)
            )
        except dual.CamError:
            networks = []
        out["networks"] = networks
    used = next((n for n in out["networks"] if n["in_use"]), None)
    if used:
        out["mode"] = "station"
        out["ssid"] = used["ssid"]
        out["signal"] = used["signal"]
        out["security"] = used["security"]
        out["message"] = f"{used['ssid']}  {out['url'] or 'no ip'}"
        return out
    if name:
        out["mode"] = "station"
        out["ssid"] = name
        out["message"] = f"{name}  {out['url'] or 'no ip'}"
        return out
    out["message"] = "wifi idle — scan or start AP"
    return out


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
    except dual.CamError:
        _nmcli(
            ["device", "wifi", "hotspot", "ifname", device,
             "con-name", AP_CON, "ssid", creds["ap_ssid"],
             "password", creds["ap_psk"]],
            timeout=30,
        )
    out = status()
    out["ap_ssid"] = creds["ap_ssid"]
    out["ap_psk"] = creds["ap_psk"]
    out["mode"] = "ap"
    out["ssid"] = creds["ap_ssid"]
    out["message"] = f"AP {creds['ap_ssid']}  {out['url'] or 'wait for ip'}"
    return out
