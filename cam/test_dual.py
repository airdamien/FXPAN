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
import live
import pano


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


if __name__ == "__main__":
    unittest.main()
