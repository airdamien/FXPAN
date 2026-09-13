#!/usr/bin/env python3
"""Parse / pair tests — no camera required."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import brightness
import dual
import gpio
import live
import pano
import settings
import wifi


DETECT = """\
Model                          Port
----------------------------------------------------------
Nikon DSC D7000                usb:020,007
Nikon DSC D7000                usb:020,012
"""

CURRENT = """\
Label: Serial Number
Readonly: 0
Type: TEXT
Current: 3000123
"""


class Parse(unittest.TestCase):
    def test_detect(self):
        rows = dual.parse_detect(DETECT)
        self.assertEqual(
            [(r["model"], r["port"]) for r in rows],
            [("Nikon DSC D7000", "usb:020,007"), ("Nikon DSC D7000", "usb:020,012")],
        )

    def test_detect_empty(self):
        self.assertEqual(dual.parse_detect("Model  Port\n----\n"), [])

    def test_current(self):
        self.assertEqual(dual.parse_current(CURRENT), "3000123")

    def test_currents(self):
        self.assertEqual(
            dual.parse_currents("Current: 400\nOther: x\nCurrent: 1/125\n"),
            ["400", "1/125"],
        )

    def test_format_shutter(self):
        self.assertEqual(dual.format_shutter("0.0250s"), "1/40")
        self.assertEqual(dual.format_shutter("1/125"), "1/125")
        self.assertEqual(dual.format_shutter("4s"), "4")
        self.assertEqual(dual.format_shutter("4"), "4")

    def test_decode_program_d7000_dial(self):
        self.assertEqual(
            dual.decode_program({
                "500e": "32790",
                "scenemode": "Night landscape",
                "expprogram": "Night Landscape",
            }),
            "SCENE · Night landscape",
        )
        self.assertEqual(dual.decode_program({"500e": "1", "expprogram": "M"}), "M")
        self.assertEqual(dual.decode_program({"500e": "32792"}), "Auto (no flash)")

    def test_widget_currents_do_not_shift(self):
        raw = (
            "Label: ISO Speed\nCurrent: 400\nCurrent: extra\n"
            "Label: White Balance\nCurrent: Auto\n"
            "Label: Exposure Program\nCurrent: M\n"
            "Label: Shutter Speed\nCurrent: 1/125\n"
        )
        self.assertEqual(
            dual.parse_widget_currents(raw),
            ["extra", "Auto", "M", "1/125"],
        )
        self.assertNotEqual(dual.parse_currents(raw), dual.parse_widget_currents(raw))

    def test_auto_iso_assigns(self):
        import web
        self.assertEqual(
            web._assignments({"iso": "Auto"}),
            [("isoauto", "On"), ("autoiso", "On")],
        )
        self.assertEqual(
            web._assignments({"iso": "400", "shutter": "Auto"}),
            [("isoauto", "Off"), ("autoiso", "Off"), ("iso", "400")],
        )
        self.assertIn(("shutterspeed", "1/125"), web._assignments({"shutter": "1/125"}))

    def test_claim_err(self):
        self.assertTrue(dual._claim_fail("Could not claim the USB device"))
        self.assertEqual(
            dual._gp_err("*** Error (-53: 'Could not claim the USB device') ***"),
            "USB busy (gvfs or ptpcamerad). Hit Detect again.",
        )

class SplitJpeg(unittest.TestCase):
    def test_two_frames_and_text(self):
        a = b"\xff\xd8AAAA\xff\xd9"
        b = b"\xff\xd8BBBB\xff\xd9"
        frames, rest = live.split_jpegs(b"Capturing...\n" + a + b[:6])
        self.assertEqual(frames, [a])
        frames2, rest2 = live.split_jpegs(rest + b[6:])
        self.assertEqual(frames2, [b])
        self.assertEqual(rest2, b"")

    def test_empty(self):
        self.assertEqual(live.split_jpegs(b"hello"), ([], b""))


class Pair(unittest.TestCase):
    def test_roundtrip(self):
        path = Path(self.id().replace(".", "_") + ".json")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        old = dual.PAIR_PATH
        dual.PAIR_PATH = path
        self.addCleanup(lambda: setattr(dual, "PAIR_PATH", old))
        dual.save_pair("111", "222")
        self.assertEqual(json.loads(path.read_text()), {"T": "111", "R": "222"})
        self.assertEqual(dual.load_pair(), {"T": "111", "R": "222"})
        dual.save_pair("111", None, replace=True)
        self.assertEqual(dual.load_pair(), {"T": "111"})
        dual.save_pair(None, "222")
        self.assertEqual(dual.load_pair(), {"T": "111", "R": "222"})
        with self.assertRaises(dual.CamError):
            dual.save_pair("111", "111", replace=True)
        dual.save_pair("111", "222", replace=True)
        self.assertEqual(dual.save_pair("222", None), {"T": "222"})
        dual.save_pair("111", "222", replace=True)
        self.assertEqual(dual.swap_pair(), {"T": "222", "R": "111"})
        self.assertEqual(dual.save_pair("", None), {"R": "111"})
        self.assertEqual(dual.swap_pair(), {"T": "111"})
        dual.save_pair("", "", replace=True)
        with self.assertRaises(dual.CamError):
            dual.swap_pair()


class Online(unittest.TestCase):
    def setUp(self):
        path = Path(self.id().replace(".", "_") + ".json")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        old = dual.PAIR_PATH
        dual.PAIR_PATH = path
        self.addCleanup(lambda: setattr(dual, "PAIR_PATH", old))

    def test_one_paired(self):
        have = dual.require_online(
            [{"role": "T", "port": "usb:1", "serial": "111", "model": "D7000"}]
        )
        self.assertEqual(list(have), ["T"])

    def test_lone_unpaired_is_t(self):
        have = dual.require_online(
            [{"role": "", "port": "usb:1", "serial": "999", "model": "D7000"}]
        )
        self.assertEqual(have["T"]["serial"], "999")

    def test_lone_unpaired_is_r_if_t_stored(self):
        dual.save_pair("111", None, replace=True)
        have = dual.require_online(
            [{"role": "", "port": "usb:1", "serial": "222", "model": "D7000"}]
        )
        self.assertEqual(list(have), ["R"])

    def test_none(self):
        with self.assertRaises(dual.CamError):
            dual.require_online([])


class LiveStart(unittest.TestCase):
    def test_start_without_cameras(self):
        old = dual.detect_bodies_cached
        dual.detect_bodies_cached = lambda timeout=120: []
        self.addCleanup(lambda: setattr(dual, "detect_bodies_cached", old))
        lv = live.Live()
        self.assertEqual(lv.start_from_usb(), {})
        self.assertFalse(lv.snapshot()["running"])

    def test_start_detect_error_is_empty(self):
        old = dual.detect_bodies_cached
        def boom(timeout=120):
            raise dual.CamError("gphoto2 timed out")
        dual.detect_bodies_cached = boom
        self.addCleanup(lambda: setattr(dual, "detect_bodies_cached", old))
        self.assertEqual(live.Live().start_from_usb(), {})


class Gpio(unittest.TestCase):
    def setUp(self):
        self.sim = Path(tempfile.mkdtemp()) / "gpio.json"
        self._old_sim = gpio.SIM_PATH
        gpio.SIM_PATH = self.sim
        self.addCleanup(lambda: setattr(gpio, "SIM_PATH", self._old_sim))

    def test_this_host_is_not_a_pi(self):
        self.assertFalse(gpio.on_pi())
        self.assertFalse(gpio.snapshot()["available"])
        self.assertEqual(gpio.snapshot()["pin"], 21)
        with self.assertRaises(dual.CamError):
            gpio.fire()

    def test_sim_shows_and_dry_fires(self):
        self.assertFalse(gpio.snapshot()["available"])
        snap = gpio.set_sim(True)
        self.assertTrue(snap["sim"])
        self.assertTrue(snap["available"])
        self.assertFalse(snap["pi"])
        info = gpio.fire()
        self.assertEqual(info["backend"], "sim")
        gpio.set_sim(False)
        with self.assertRaises(dual.CamError):
            gpio.fire()

    def test_model_detects_pi(self):
        path = Path(tempfile.mkdtemp()) / "model"
        path.write_bytes(b"Raspberry Pi 5 Model B Rev 1.0\x00")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        self.assertTrue(gpio.on_pi(path))
        path.write_bytes(b"Apple Mac")
        self.assertFalse(gpio.on_pi(path))

    def test_find_chip_prefers_rp1(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        (root / "gpiochip0").mkdir()
        (root / "gpiochip0" / "label").write_text("unused\n")
        (root / "gpiochip4").mkdir()
        (root / "gpiochip4" / "label").write_text("pinctrl-rp1\n")
        self.assertEqual(gpio.find_chip(root), "/dev/gpiochip4")

    def test_fire_mock_drive(self):
        seen = []

        def drive(pin, pulse_s):
            seen.append((pin, pulse_s))
            return "mock"

        info = gpio.fire(drive=drive)
        self.assertEqual(seen, [(21, 0.3)])
        self.assertEqual(info["pin"], 21)
        self.assertEqual(info["ms"], 300)
        self.assertEqual(info["backend"], "mock")


LIST_FILES = """\
There are 2 files in folder '/store_00010001/DCIM/100D7000':
#1     DSC_0001.JPG               rd  4500 KB 4928x3264 image/jpeg
#2     DSC_0002.NEF               rd    20 MB 4928x3264 image/x-nikon-nef
There are 0 files in folder '/store_00010001/DCIM':
"""


class CardPull(unittest.TestCase):
    def test_parse_list_files(self):
        rows = dual.parse_list_files(LIST_FILES)
        self.assertEqual(
            [(r["n"], r["name"]) for r in rows],
            [(1, "DSC_0001.JPG"), (2, "DSC_0002.NEF")],
        )
        self.assertEqual(rows[0]["folder"], "/store_00010001/DCIM/100D7000")

    def test_wait_new_images(self):
        calls = {"n": 0}
        before = [{"folder": "/dcim", "name": "A.JPG", "n": 1}]

        def fake(_port):
            calls["n"] += 1
            if calls["n"] < 3:
                raise dual.CamError("busy")
            return before + [{"folder": "/dcim", "name": "B.JPG", "n": 2}]

        new = dual.wait_new_images(
            "usb:1", before, timeout=2, interval=0.01, list_fn=fake
        )
        self.assertEqual(new[0]["name"], "B.JPG")

    def test_wait_timeout(self):
        before = [{"folder": "/dcim", "name": "A.JPG", "n": 1}]
        with self.assertRaises(dual.CamError):
            dual.wait_new_images(
                "usb:1", before, timeout=0.05, interval=0.01,
                list_fn=lambda _p: before,
            )


class Pano(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(self.root, ignore_errors=True))

    def _jpeg(self, name, color, w=40, h=20):
        dest = self.root / name
        subprocess.run(
            ["magick", "-size", f"{w}x{h}", f"xc:{color}", str(dest)],
            check=True,
            capture_output=True,
        )
        return dest

    def _exif_jpeg(self, name, iso=400, shutter=(1, 125), program=1, wb=0):
        dest = self._jpeg(name, "red")
        model = b"NIKON D7000\x00"
        pu16 = lambda n: n.to_bytes(2, "little")
        pu32 = lambda n: n.to_bytes(4, "little")
        def entry(tag, typ, cnt, val4):
            return pu16(tag) + pu16(typ) + pu32(cnt) + val4
        ifd0_off, ifd0_len = 8, 2 + 24 + 4
        model_off = ifd0_off + ifd0_len
        exif_off = model_off + len(model)
        exif_len = 2 + 48 + 4
        rat_off = exif_off + exif_len
        tiff = (
            b"II*\x00" + pu32(8)
            + pu16(2)
            + entry(0x0110, 2, len(model), pu32(model_off))
            + entry(0x8769, 4, 1, pu32(exif_off))
            + pu32(0)
            + model
            + pu16(4)
            + entry(0x829A, 5, 1, pu32(rat_off))
            + entry(0x8827, 3, 1, pu16(iso) + b"\x00\x00")
            + entry(0x8822, 3, 1, pu16(program) + b"\x00\x00")
            + entry(0xA403, 3, 1, pu16(wb) + b"\x00\x00")
            + pu32(0)
            + pu32(shutter[0]) + pu32(shutter[1])
        )
        app1 = b"Exif\x00\x00" + tiff
        jpeg = dest.read_bytes()
        dest.write_bytes(b"\xff\xd8" + b"\xff\xe1" + (len(app1) + 2).to_bytes(2, "big") + app1 + jpeg[2:])
        return dest

    def test_read_exif(self):
        self.assertEqual(pano.read_exif(self._jpeg("plain.jpg", "red")), {})
        info = pano.read_exif(self._exif_jpeg("shot.jpg"))
        self.assertEqual(info["iso"], "400")
        self.assertEqual(info["shutter"], "1/125")
        self.assertEqual(info["program"], "M")
        self.assertEqual(info["wb"], "Auto")
        self.assertEqual(info["model"], "D7000")

    def test_list_pairs_stores_exif(self):
        self._exif_jpeg("T_20260101_120000.jpg", iso=640, shutter=(1, 60))
        self._exif_jpeg("R_20260101_120000.jpg", iso=100, shutter=(1, 125), program=3)
        rows = pano.list_pairs(self.root)
        ready = [row for row in rows if row["ready"]][0]
        self.assertEqual(ready["exif"]["T"]["iso"], "640")
        self.assertEqual(ready["exif"]["T"]["shutter"], "1/60")
        self.assertEqual(ready["exif"]["R"]["program"], "A")
        self.assertTrue((self.root / "X_20260101_120000.json").is_file())
        pano.delete_stamp("20260101_120000", self.root)
        self.assertFalse((self.root / "X_20260101_120000.json").is_file())

    def test_list_pairs(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        self._jpeg("T_lonely.jpg", "red")
        rows = pano.list_pairs(self.root)
        ready = [row for row in rows if row["ready"]]
        self.assertEqual(len(ready), 1)
        self.assertEqual(ready[0]["stamp"], "20260101_120000")
        self.assertEqual(ready[0]["t"], "T_20260101_120000.jpg")

    def test_stitch_status_stays_on_pair(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        pano._write_sidecar(
            self.root, "20260101_120000",
            {"mode": "open", "phase": "error", "error": "SIFT failed", "message": "SIFT failed"},
        )
        row = pano.list_pairs(self.root)[0]
        self.assertEqual(row["stitch"]["phase"], "error")
        self.assertEqual(row["stitch"]["error"], "SIFT failed")
        pano._write_sidecar(
            self.root, "20260101_120000",
            {"mode": "open", "phase": "done", "error": "", "message": "open  affine  70×20"},
        )
        row = pano.list_pairs(self.root)[0]
        self.assertEqual(row["stitch"]["phase"], "done")
        self.assertEqual(row["stitch"]["message"], "open  affine  70×20")

    def test_list_pairs_newest_first(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        self._jpeg("T_20260913_150000.jpg", "red")
        self._jpeg("R_20260913_150000.jpg", "blue")
        stamps = [row["stamp"] for row in pano.list_pairs(self.root)]
        self.assertEqual(stamps[0], "20260913_150000")
        self.assertEqual(stamps[1], "20260101_120000")

    def test_stitch_width(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        info = pano.stitch_stamp(
            "20260101_120000", overlap=0.25, flip_r=False, mode="blend", root=self.root
        )
        self.assertEqual(info["width"], 70)
        self.assertEqual(info["height"], 20)
        self.assertTrue((self.root / "P_20260101_120000.jpg").is_file())
        rows = pano.list_pairs(self.root)
        self.assertEqual(rows[0]["pano"], "P_20260101_120000.jpg")
        self.assertEqual(rows[0]["stitch"].get("mode"), "blend")

    def test_open_import(self):
        pano._venv_site()
        try:
            from stitching import AffineStitcher, Stitcher
        except ImportError:
            self.skipTest("stitching-headless not installed")
        self.assertTrue(callable(Stitcher) and callable(AffineStitcher))

    def test_find_overlap_marker(self):
        full = self.root / "full.jpg"
        t = self.root / "t.jpg"
        r = self.root / "r.jpg"
        subprocess.run(
            ["magick", "-size", "136x40", "plasma:fractal", str(full)],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["magick", str(full), "-crop", "80x40+0+0", "+repage", str(t)],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["magick", str(full), "-crop", "80x40+56+0", "+repage", str(r)],
            check=True, capture_output=True,
        )
        found = pano.find_overlap(t, r, try_flip=False)
        self.assertFalse(found["flip_r"])
        self.assertGreater(found["overlap"], 0.20)
        self.assertLess(found["overlap"], 0.40)
        self.assertLess(abs(found["dy"]), 4)

    def test_resolve_rejects_traversal(self):
        with self.assertRaises(dual.CamError):
            pano.resolve("../secret.jpg", self.root)

    def test_delete_stamp_and_side(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        self._jpeg("P_20260101_120000.jpg", "green")
        pano.delete_stamp("20260101_120000", self.root, sides=["P"])
        self.assertFalse((self.root / "P_20260101_120000.jpg").is_file())
        self.assertTrue((self.root / "T_20260101_120000.jpg").is_file())
        pano.delete_stamp("20260101_120000", self.root)
        self.assertEqual(pano.list_pairs(self.root), [])

    def test_before_today_and_keep_last(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        self._jpeg("T_20260911_100000.jpg", "red")
        self._jpeg("R_20260911_100000.jpg", "blue")
        self._jpeg("T_20260911_110000.jpg", "red")
        info = pano.delete_before_today(self.root, today="20260911")
        self.assertEqual(info["removed"], ["20260101_120000"])
        stamps = {row["stamp"] for row in pano.list_pairs(self.root)}
        self.assertEqual(stamps, {"20260911_100000", "20260911_110000"})
        for i in range(6):
            self._jpeg(f"T_20260911_12000{i}.jpg", "red")
        kept = pano.keep_last(5, self.root)
        self.assertEqual(kept["count"], 3)
        self.assertEqual(len(pano.list_pairs(self.root)), 5)

    def test_stitch_queue_serial(self):
        pano._jobs.clear()
        pano._queue.clear()
        gate = threading.Event()
        started = []

        def fake(stamp, **_kw):
            started.append(stamp)
            self.assertTrue(gate.wait(2))
            return {
                "stamp": stamp, "message": f"done {stamp}", "width": 1, "height": 1,
                "mode": "open", "overlap": 0.2, "overlap_frac": 0.2, "dy": 0,
                "flip_r": False, "file": f"P_{stamp}.jpg",
            }

        old = pano.stitch_stamp
        pano.stitch_stamp = fake
        try:
            first = pano.start_stitch("20260101_120000", mode="open", root=self.root)
            second = pano.start_stitch("20260101_130000", mode="open", root=self.root)
            self.assertEqual(first["phase"], "start")
            self.assertTrue(first["running"])
            self.assertEqual(second["phase"], "queued")
            stat = pano.queue_status()
            self.assertTrue(stat["running"])
            self.assertEqual(stat["queued"], 1)
            self.assertIn("queued", stat["message"])
            self.assertTrue(second["running"])
            with self.assertRaises(dual.CamError):
                pano.start_stitch("20260101_120000", mode="open", root=self.root)
            deadline = time.time() + 2
            while time.time() < deadline and started != ["20260101_120000"]:
                time.sleep(0.01)
            self.assertEqual(started, ["20260101_120000"])
            gate.set()
            deadline = time.time() + 2
            while time.time() < deadline:
                if pano.job_get("20260101_130000").get("phase") == "done":
                    break
                time.sleep(0.02)
            self.assertEqual(pano.job_get("20260101_120000")["phase"], "done")
            self.assertEqual(pano.job_get("20260101_130000")["phase"], "done")
            self.assertEqual(started, ["20260101_120000", "20260101_130000"])
        finally:
            gate.set()
            pano.stitch_stamp = old
            pano._jobs.clear()
            pano._queue.clear()


class CopyMaster(unittest.TestCase):
    def test_assignments_skip_flash(self):
        out = dual.assignments_from_status({
            "iso": "400",
            "isoauto": "Off",
            "shutterspeed": "1/125",
            "imagequality": "JPEG Fine",
            "whitebalance": "Auto",
            "exposurecompensation": "0",
            "expprogram": "M",
            "flashmode": "Fill flash",
            "flash": "On",
            "batterylevel": "75%",
            "serialnumber": "123",
            "capturetarget": "Memory card",
        })
        keys = [k for k, _ in out]
        self.assertEqual(
            keys,
            [
                "isoauto", "autoiso", "iso", "shutterspeed",
                "imagequality", "whitebalance", "exposurecompensation", "expprogram",
            ],
        )
        self.assertNotIn("flashmode", keys)
        self.assertNotIn("flash", keys)
        self.assertIn(("iso", "400"), out)
        self.assertIn(("expprogram", "M"), out)

    def test_assignments_auto_iso(self):
        keys = [k for k, _ in dual.assignments_from_status({
            "iso": "Auto", "isoauto": "On", "shutterspeed": "1/60",
        })]
        self.assertIn("isoauto", keys)
        self.assertNotIn("iso", keys)

    def test_copy_from_master(self):
        calls = []

        def status(row):
            return {
                "iso": "200", "isoauto": "Off", "shutterspeed": "1/250",
                "whitebalance": "Auto", "imagequality": "JPEG Fine",
                "exposurecompensation": "0", "expprogram": "M",
                "flashmode": "Rear",
            }

        def set_one(port, assignments):
            calls.append((port, list(assignments)))
            return []

        old_status, old_set = dual._status_one, dual._set_one
        dual._status_one = status
        dual._set_one = set_one
        try:
            have = {
                "T": {"role": "T", "port": "usb:1", "model": "D7000"},
                "R": {"role": "R", "port": "usb:2", "model": "D7000"},
            }
            info = dual.copy_from_master(have, "T")
            self.assertEqual(info["master"], "T")
            self.assertEqual(info["slave"], "R")
            self.assertEqual(calls[0][0], "usb:2")
            self.assertNotIn("flashmode", [k for k, _ in calls[0][1]])
            self.assertIn("T → R", info["message"])
        finally:
            dual._status_one = old_status
            dual._set_one = old_set


class Settings(unittest.TestCase):
    def setUp(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        self._old = settings.PATH
        settings.PATH = root / "settings.json"
        self.addCleanup(lambda: setattr(settings, "PATH", self._old))

    def test_pi_defaults_both_on(self):
        self.assertEqual(
            settings.load(pi=True),
            {
                "download": True, "gpio": True, "flip_r": False, "overlap": 0.20,
                "sync": True, "master": "T",
            },
        )

    def test_mac_defaults_both_off(self):
        self.assertEqual(
            settings.load(pi=False),
            {
                "download": False, "gpio": False, "flip_r": False, "overlap": 0.20,
                "sync": True, "master": "T",
            },
        )

    def test_save_survives_reload(self):
        settings.save(
            {"download": False, "gpio": True, "flip_r": True, "overlap": 0.25},
            pi=True,
        )
        self.assertEqual(
            settings.load(pi=True),
            {
                "download": False, "gpio": True, "flip_r": True, "overlap": 0.25,
                "sync": True, "master": "T",
            },
        )
        settings.save({"download": True}, pi=True)
        self.assertEqual(settings.load(pi=True)["overlap"], 0.25)
        self.assertTrue(settings.load(pi=True)["flip_r"])

    def test_overlap_percent(self):
        settings.save({"overlap": 18}, pi=True)
        self.assertEqual(settings.load(pi=True)["overlap"], 0.18)

    def test_master_and_sync(self):
        settings.save({"master": "R", "sync": False}, pi=True)
        self.assertEqual(settings.load(pi=True)["master"], "R")
        self.assertFalse(settings.load(pi=True)["sync"])
        settings.save({"master": "X"}, pi=True)
        self.assertEqual(settings.load(pi=True)["master"], "R")

    def test_brightness_persists(self):
        settings.save({"brightness": 40}, pi=True)
        self.assertEqual(settings.load(pi=True)["brightness"], 40)
        settings.save({"download": False}, pi=True)
        self.assertEqual(settings.load(pi=True)["brightness"], 40)
        settings.save({"brightness": 0}, pi=True)
        self.assertEqual(settings.load(pi=True)["brightness"], 40)

    def test_shoot_target(self):
        self.assertEqual(
            settings.shoot_target({"gpio": True, "download": True}, {"available": True}),
            "gpio",
        )
        self.assertEqual(
            settings.shoot_target({"gpio": True, "download": True}, {"available": False}),
            "download",
        )
        self.assertEqual(
            settings.shoot_target({"gpio": False, "download": False}, {"available": True}),
            "card",
        )


class Brightness(unittest.TestCase):
    def test_parse_getvcp(self):
        cur, mx = brightness.parse_getvcp(bytes([
            0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x06, 0xC6,
        ]))
        self.assertEqual((cur, mx), (6, 100))

    def test_clamp(self):
        self.assertEqual(brightness.clamp(6), 6)
        self.assertEqual(brightness.clamp(0), 1)
        self.assertEqual(brightness.clamp(140), 100)
        self.assertIsNone(brightness.clamp("x"))

    def test_invert(self):
        self.assertEqual(brightness.invert(6, 100), 94)
        self.assertEqual(brightness.invert(94, 100), 6)
        self.assertEqual(brightness.invert(100, 100), 1)

    def test_find_bus(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        a = root / "card1-HDMI-A-1"
        b = root / "card1-HDMI-A-2"
        a.mkdir(); b.mkdir()
        (a / "status").write_text("disconnected\n")
        (b / "status").write_text("connected\n")
        i2c = root / "i2c-21"
        i2c.mkdir()
        (b / "ddc").symlink_to(i2c)
        self.assertEqual(brightness.find_bus(root), 21)
        self.assertIsNone(brightness.find_bus(root / "missing"))


class Wifi(unittest.TestCase):
    def setUp(self):
        self.calls = []
        root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        self._old_nmcli = wifi._nmcli
        wifi._nmcli = self.fake
        self.addCleanup(lambda: setattr(wifi, "_nmcli", self._old_nmcli))
        self._old_path = wifi.PATH
        wifi.PATH = root / "wifi.json"
        self.addCleanup(lambda: setattr(wifi, "PATH", self._old_path))

    def fake(self, args, timeout=25):
        self.calls.append(list(args))
        if "DEVICE,TYPE,STATE" in args:
            return "wlan0:wifi:connected\n"
        if "IP4.ADDRESS" in args:
            return "IP4.ADDRESS:192.0.2.10/24\n"
        if "--active" in args:
            return "Home:wifi:wlan0\n"
        if "-g" in args:
            return "infrastructure\n"
        if "list" in args:
            return "*:Home:88:WPA2\n :Cafe:40:\n"
        return ""

    def test_fields_unescape(self):
        self.assertEqual(
            wifi._fields(r"*:cafe\:bar:80:WPA2"),
            ["*", "cafe:bar", "80", "WPA2"],
        )

    def test_parse_keeps_strongest_and_open(self):
        nets = wifi.parse_networks(" :Home:20:WPA2\n*:Home:88:WPA2\n :Cafe:40:\n")
        self.assertEqual([n["ssid"] for n in nets], ["Home", "Cafe"])
        self.assertTrue(nets[0]["in_use"])
        self.assertEqual(nets[0]["signal"], 88)
        self.assertEqual(nets[1]["security"], "")

    def test_join_needs_ssid(self):
        with self.assertRaises(dual.CamError):
            wifi.join("  ")

    def test_join_open(self):
        out = wifi.join("Cafe")
        self.assertTrue(any("connect" in a and "Cafe" in a for a in self.calls))
        self.assertFalse(any("password" in a for a in self.calls))
        self.assertEqual(out["ssid"], "Home")
        self.assertIn("192.0.2.10", out["url"])

    def test_ap_on(self):
        def fake(args, timeout=25):
            self.calls.append(list(args))
            if "DEVICE,TYPE,STATE" in args:
                return "wlan0:wifi:disconnected\n"
            if "--active" in args:
                return "D12600-AP:wifi:wlan0\n"
            if "-g" in args:
                return "ap\n"
            if "IP4.ADDRESS" in args:
                return "IP4.ADDRESS:10.42.0.1/24\n"
            if args[:2] == ["-f", "NAME"]:
                return "D12600-AP\n"
            return ""
        wifi._nmcli = fake
        out = wifi.set_ap(True)
        self.assertEqual(out["mode"], "ap")
        self.assertEqual(out["ap_ssid"], "D12600")
        self.assertGreaterEqual(len(out["ap_psk"]), 8)
        self.assertIn("10.42.0.1", out["url"])


if __name__ == "__main__":
    unittest.main()
