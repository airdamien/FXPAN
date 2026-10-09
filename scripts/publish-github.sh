#!/usr/bin/env bash
# Push master to the public GitHub remote with private hostnames removed
# from every commit. The replacements live in scripts/github-replace.txt,
# one `old==>new` per line, and that file is gitignored.
# Gitea stays the prime remote and keeps the full history.
# A plain `git push github` would upload the older commits.
#
#   ./scripts/publish-github.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/scripts/github-replace.txt"
REMOTE="${FXPAN_GITHUB:-git@github.com:airdamien/FXPAN.git}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ ! -f "$MAP" ]]; then
  echo "write scripts/github-replace.txt first (old==>new, one per line)" >&2
  exit 1
fi

git clone "$ROOT" "$WORK/tree"
cd "$WORK/tree"
export FXPAN_MAP="$MAP"
export FILTER_BRANCH_SQUELCH_WARNING=1
git filter-branch -f --tree-filter 'python3 - "$FXPAN_MAP" <<"PY"
import pathlib, subprocess, sys
pairs = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "==>" not in line:
        continue
    old, new = line.split("==>", 1)
    if old:
        pairs.append((old, new))
files = set()
for old, _new in pairs:
    found = subprocess.run(
        ["git", "grep", "-l", "-I", "-F", old],
        capture_output=True, text=True)
    files.update(p for p in found.stdout.splitlines() if p)
for name in files:
    path = pathlib.Path(name)
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    rewritten = text
    for old, new in pairs:
        rewritten = rewritten.replace(old, new)
    if rewritten != text:
        path.write_text(rewritten, encoding="utf-8", errors="surrogateescape")
PY
' master

python3 - "$MAP" << 'PY'
import subprocess, sys
from pathlib import Path
olds = []
for line in Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "==>" not in line:
        continue
    old, _new = line.split("==>", 1)
    if old:
        olds.append(old)
failed = False
for old in olds:
    log = subprocess.run(["git", "log", "-S", old, "--oneline"], capture_output=True, text=True)
    if log.stdout.strip():
        print(f"still present after filtering: {old}", file=sys.stderr)
        print(log.stdout, file=sys.stderr)
        failed = True
if failed:
    sys.exit(1)
PY
git push "$REMOTE" master
