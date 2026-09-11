#!/usr/bin/env python3
"""Parse / pair tests — no camera required."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dual
import live


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


if __name__ == "__main__":
    unittest.main()
