#!/bin/sh
# Pi: venv with Debian OpenCV + OpenStitching (PANO Open mode).
set -eu
CAM="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$CAM/.venv"

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-venv python3-pip python3-numpy python3-opencv

python3 -m venv --system-site-packages "$VENV"
"$VENV/bin/pip" install -U pip
# Do not let pip pull opencv-python-headless; use apt cv2.
"$VENV/bin/pip" install largestinteriorrectangle
"$VENV/bin/pip" install --no-deps "stitching-headless>=0.7"
"$VENV/bin/python3" -c "
import cv2
from stitching import AffineStitcher, Stitcher
print('opencv', cv2.__version__)
print('stitching', AffineStitcher, Stitcher)
"
