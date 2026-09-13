#!/usr/bin/env python3
"""Parse / pair tests — no camera required."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dual
import gpio
import live
import pano
import settings


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

    def test_claim_err(self):
        self.assertTrue(dual._claim_fail("Could not claim the USB device"))
        self.assertEqual(
            dual._gp_err("*** Error (-53: 'Could not claim the USB device') ***"),
            "USB busy (macOS ptpcamerad). Hit Status again.",
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

    def test_list_pairs(self):
        self._jpeg("T_20260101_120000.jpg", "red")
        self._jpeg("R_20260101_120000.jpg", "blue")
        self._jpeg("T_lonely.jpg", "red")
        rows = pano.list_pairs(self.root)
        ready = [row for row in rows if row["ready"]]
        self.assertEqual(len(ready), 1)
        self.assertEqual(ready[0]["stamp"], "20260101_120000")
        self.assertEqual(ready[0]["t"], "T_20260101_120000.jpg")

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


class Settings(unittest.TestCase):
    def setUp(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        self._old = settings.PATH
        settings.PATH = root / "settings.json"
        self.addCleanup(lambda: setattr(settings, "PATH", self._old))

    def test_pi_defaults_both_on(self):
        self.assertEqual(settings.load(pi=True), {"download": True, "gpio": True})

    def test_mac_defaults_both_off(self):
        self.assertEqual(settings.load(pi=False), {"download": False, "gpio": False})

    def test_save_survives_reload(self):
        settings.save({"download": False, "gpio": True}, pi=True)
        self.assertEqual(settings.load(pi=True), {"download": False, "gpio": True})

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


if __name__ == "__main__":
    unittest.main()
