#!/usr/bin/env bash
# Patch claude-plugins-official/telegram server.ts to relax the orphan
# watchdog. The vanilla watchdog fires every 5s on three signals — PPID
# drift, stdin.destroyed, stdin.readableEnded — and in practice we observed
# false positives during healthy Claude Code sessions (bun run wrapper
# transiently appears to reparent or stdin reports readableEnded). Result:
# MCP self-terminates every 15–20 min during active sessions.
#
# This patch:
#   - 5s  → 30s   (less aggressive polling)
#   - drop process.ppid-drift check
#   - drop stdin.readableEnded check
#   - keep stdin.destroyed (the unambiguous CC-died signal)
#
# Idempotent (re-runs detect the marker comment and exit 0). A backup of
# the original file is kept next to the patched version.
set -euo pipefail

PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
SRC=""
if [ -d "$PLUGIN_BASE" ]; then
  for v in "$PLUGIN_BASE"/0.0.* ; do
    if [ -f "$v/server.ts" ]; then
      SRC="$v/server.ts"
      break
    fi
  done
fi

if [ -z "$SRC" ]; then
  echo "[patch-telegram-watchdog] no telegram plugin server.ts found under $PLUGIN_BASE — skipping"
  exit 0
fi

MARKER='ECC_WATCHDOG_PATCHED_v1'
if grep -q "$MARKER" "$SRC"; then
  echo "[patch-telegram-watchdog] already patched ($SRC)"
  exit 0
fi

BACKUP="$SRC.orig.$(date +%s)"
cp "$SRC" "$BACKUP"

python3 - "$SRC" <<'PYTHON'
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()

old = '''// Orphan watchdog: stdin events above don\'t reliably fire when the parent
// chain (`bun run` wrapper → shell → us) is severed by a crash. Poll for
// reparenting (POSIX) or a dead stdin pipe and self-terminate.
const bootPpid = process.ppid
setInterval(() => {
  const orphaned =
    (process.platform !== \'win32\' && process.ppid !== bootPpid) ||
    process.stdin.destroyed ||
    process.stdin.readableEnded
  if (orphaned) shutdown()
}, 5000).unref()'''

new = '''// ECC_WATCHDOG_PATCHED_v1 — local mitigation of false-positive shutdowns.
// Vanilla check (5s + PPID-drift + readableEnded) fired during healthy CC
// sessions (bun run wrapper sometimes reparents transiently or stdin reports
// readableEnded). Now: 30s interval, only stdin.destroyed.
const bootPpid = process.ppid
setInterval(() => {
  if (process.stdin.destroyed) shutdown()
}, 30000).unref()'''

if old not in s:
    sys.stderr.write("[patch-telegram-watchdog] verbatim watchdog block not found "
                     "— plugin likely upgraded; aborting safely without changes\n")
    sys.exit(2)

s = s.replace(old, new)
with open(path, 'w') as f:
    f.write(s)
sys.stderr.write(f"[patch-telegram-watchdog] applied to {path}\n")
PYTHON

echo "[patch-telegram-watchdog] backup saved at $BACKUP"
