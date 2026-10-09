#!/usr/bin/env bash
# Resolve the kiosk ssh target. The address is not stored in the repo.
#   1. an explicit user@host argument
#   2. $FXPAN_PI
#   3. scripts/pi.target, one line, gitignored
pi_target() {
  local arg="${1-}"
  if [[ -n "$arg" && "$arg" != -* ]]; then
    printf '%s\n' "$arg"
    return 0
  fi
  if [[ -n "${FXPAN_PI:-}" ]]; then
    printf '%s\n' "$FXPAN_PI"
    return 0
  fi
  local file
  file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pi.target"
  if [[ -f "$file" ]]; then
    tr -d '[:space:]' < "$file"
    printf '\n'
    return 0
  fi
  echo "Pass user@host, set FXPAN_PI, or write scripts/pi.target (one line, not committed)." >&2
  return 1
}
