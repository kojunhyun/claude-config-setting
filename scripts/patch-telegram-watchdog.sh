#!/usr/bin/env bash
# Patch claude-plugins-official/telegram server.ts with two local mitigations:
#
#   v1 (orphan watchdog):  5s+PPID+readableEnded → 30s+stdin.destroyed only.
#                          The vanilla check fired during healthy CC sessions
#                          (bun run wrapper sometimes appears to reparent or
#                          stdin reports readableEnded transiently).
#
#   v2 (stale killer):     SIGTERM the previous bot.pid holder ONLY when it
#                          is a true orphan (PPID=1). The vanilla code
#                          SIGTERMs unconditionally, so every cron-spawned
#                          claude session (e.g. hourly /config-push) kills
#                          the user's interactive Telegram bridge each time
#                          its scheduler fires. With this patch, cohabitants
#                          recognize the active session and yield (exit 0)
#                          instead of fighting.
#
# Each patch has its own marker and is applied independently. A backup of
# the original file is kept next to the patched version.
set -euo pipefail

# Patch BOTH plugin caches: the canonical $HOME/.claude/plugins/cache and
# the config-repo's plugins/cache/. Claude Code resolves CLAUDE_PLUGIN_ROOT
# to one or the other depending on how it was launched; we observed it
# choosing the config-repo path in interactive sessions. Patch all matches;
# idempotent markers prevent double-application.
PLUGIN_BASES=(
  "$HOME/.claude/plugins/cache/claude-plugins-official/telegram"
  "${CLAUDE_CONFIG_DIR:-$HOME/00_Project/00_Claude-Config-Setting}/plugins/cache/claude-plugins-official/telegram"
)
SOURCES=()
for base in "${PLUGIN_BASES[@]}"; do
  if [ -d "$base" ]; then
    for v in "$base"/0.0.* ; do
      if [ -f "$v/server.ts" ]; then
        SOURCES+=("$v/server.ts")
      fi
    done
  fi
done

if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "[patch-telegram] no telegram plugin server.ts found in any base — skipping"
  exit 0
fi

for SRC in "${SOURCES[@]}"; do
echo "[patch-telegram] === target: $SRC ==="

BACKUP_TAKEN=0
take_backup_once() {
  if [ "$BACKUP_TAKEN" = 0 ]; then
    local BACKUP="$SRC.orig.$(date +%s)"
    cp "$SRC" "$BACKUP"
    echo "[patch-telegram] backup saved at $BACKUP"
    BACKUP_TAKEN=1
  fi
}

# ----- v1: orphan watchdog relaxation -----
if grep -q "ECC_WATCHDOG_PATCHED_v1" "$SRC"; then
  echo "[patch-telegram] v1 (watchdog) already applied"
else
  take_backup_once
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
    sys.stderr.write("[patch-telegram] v1: verbatim watchdog block not found "
                     "— plugin likely upgraded; aborting v1 safely\n")
    sys.exit(2)

s = s.replace(old, new)
with open(path, 'w') as f:
    f.write(s)
sys.stderr.write("[patch-telegram] v1 (watchdog) applied\n")
PYTHON
fi

# ----- v2: stale killer — yield to active siblings -----
if grep -q "ECC_STALE_KILLER_PATCHED_v1" "$SRC"; then
  echo "[patch-telegram] v2 (stale killer) already applied"
else
  take_backup_once
  python3 - "$SRC" <<'PYTHON'
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()

old = '''try {
  const stale = parseInt(readFileSync(PID_FILE, \'utf8\'), 10)
  if (stale > 1 && stale !== process.pid) {
    process.kill(stale, 0)
    process.stderr.write(`telegram channel: replacing stale poller pid=${stale}\\n`)
    process.kill(stale, \'SIGTERM\')
  }
} catch {}'''

new = '''try {
  const stale = parseInt(readFileSync(PID_FILE, \'utf8\'), 10)
  if (stale > 1 && stale !== process.pid) {
    process.kill(stale, 0)  // throws if dead, falls through to writeFileSync
    // ECC_STALE_KILLER_PATCHED_v1 — distinguish active CC-child vs true
    // orphan to prevent cron-spawned cohabitants (e.g. hourly /config-push)
    // from SIGTERMing the user\'s interactive Telegram bridge.
    let isOrphan = false
    try {
      const { execSync } = require(\'child_process\')
      const ppidOut = execSync(`ps -o ppid= -p ${stale}`, { encoding: \'utf8\' })
      isOrphan = parseInt(ppidOut.trim(), 10) === 1
    } catch {}
    if (isOrphan) {
      process.stderr.write(`telegram channel: replacing stale orphan poller pid=${stale}\\n`)
      process.kill(stale, \'SIGTERM\')
    } else {
      process.stderr.write(`telegram channel: another active poller pid=${stale} (PPID!=1) — yielding\\n`)
      process.exit(0)
    }
  }
} catch {}'''

if old not in s:
    sys.stderr.write("[patch-telegram] v2: verbatim stale-killer block not found "
                     "— plugin likely upgraded; aborting v2 safely\n")
    sys.exit(2)

s = s.replace(old, new)
with open(path, 'w') as f:
    f.write(s)
sys.stderr.write("[patch-telegram] v2 (stale killer) applied\n")
PYTHON
fi

done  # end for SRC in SOURCES
