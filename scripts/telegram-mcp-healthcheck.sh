#!/usr/bin/env bash
# Telegram MCP healthcheck — runs every 2 min via launchd (macOS) / cron (Linux).
#
# Three failure modes are handled:
#   1. bun MCP process fully dead     → notify (so user knows to /mcp reconnect)
#   2. bun process is orphan (PPID=1) → kill it (frees Telegram token slot,
#                                       then notify so user runs /mcp)
#   3. multiple bun processes (race)  → kill orphans, keep the freshest
#
# Mode (2) is the actual recurring root cause: when a Claude Code session
# exits, its child bun is inherited by init (PPID=1) and keeps polling. The
# next CC session's bun gets 409 Conflict from Telegram (one getUpdates
# consumer per token), retries 8 times, then exits — CC shows MCP disconnected
# until the orphan is cleared. The plugin's own stale-killer only fires if
# bot.pid points to the orphan; after a few cycles bot.pid drifts and the
# orphan becomes invisible to the plugin.
#
# Exit codes:
#   0 — healthy, or down/orphan-handled-but-already-alerted within window
#   2 — alert dispatched (down or orphan cleanup)
set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
STATE_DIR="${HOME}/.claude/state"
LOG_FILE="${LOG_DIR}/telegram-mcp-healthcheck.log"
STATE_FILE="${STATE_DIR}/telegram-mcp-last-alert"
ENV_FILE="${HOME}/.claude/channels/telegram/.env"
ACCESS_FILE="${HOME}/.claude/channels/telegram/access.json"
PID_FILE="${HOME}/.claude/channels/telegram/bot.pid"
SUPPRESS_SEC=1800   # one alert per 30 min while still down

PATTERN='telegram/0\.[0-9]+\.[0-9]+.*server\.ts|--cwd[= ].*telegram/0\.[0-9]+\.[0-9]+'

mkdir -p "$LOG_DIR" "$STATE_DIR"

log() {
  printf '%s [healthcheck] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >> "$LOG_FILE"
}

send_alert() {
  local kind="$1" detail="$2"
  local now
  now=$(date +%s)

  if [[ -f "$STATE_FILE" ]]; then
    local last
    last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    if (( now - last < SUPPRESS_SEC )); then
      log "${kind}: alert suppressed (last=${last}, now=${now}) — ${detail}"
      return 0
    fi
  fi
  echo "$now" > "$STATE_FILE"

  if [[ -r "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi

  local host ts msg chat_id=""
  host="$(hostname -s 2>/dev/null || uname -n)"
  ts="$(date '+%H:%M')"
  case "$kind" in
    DOWN)
      msg="📡 텔레그램 MCP 가 ${host} 에서 응답하지 않습니다 (${ts}). Claude Code 에서 /mcp 로 재연결해주세요."
      ;;
    ORPHAN_CLEANED)
      msg="🧹 텔레그램 MCP orphan 정리됨 (${host} ${ts}): ${detail}. Claude Code 에서 /mcp 로 재연결해주세요."
      ;;
    *)
      msg="ℹ️ 텔레그램 MCP healthcheck (${host} ${ts}): ${detail}"
      ;;
  esac

  if [[ -r "$ACCESS_FILE" ]]; then
    if command -v jq >/dev/null 2>&1; then
      chat_id=$(jq -r '.allowFrom[0] // empty' "$ACCESS_FILE" 2>/dev/null || true)
    elif command -v python3 >/dev/null 2>&1; then
      chat_id=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
    a=d.get("allowFrom",[])
    print(a[0] if a else "")
except: pass' "$ACCESS_FILE" 2>/dev/null || true)
    fi
  fi

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "$chat_id" ]]; then
    if curl -s -m 10 -X POST \
         "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         --data-urlencode "chat_id=${chat_id}" \
         --data-urlencode "text=${msg}" >/dev/null 2>&1; then
      log "${kind}: direct API sent to chat_id=${chat_id}"
    else
      log "${kind}: direct API send failed (network or token issue)"
    fi
  else
    log "${kind}: direct API skipped (token=${TELEGRAM_BOT_TOKEN:+present} chat_id=${chat_id:-empty})"
  fi

  if command -v tmux >/dev/null 2>&1; then
    local pane
    pane=$(tmux list-panes -a -F '#{pane_id}|#{pane_current_command}' 2>/dev/null \
      | awk -F'|' '$2 ~ /^(claude|node|bun|deno)$/ { print $1; exit }' || true)
    if [[ -n "${pane:-}" ]]; then
      tmux send-keys -l -t "$pane" "/mcp" 2>/dev/null || true
      tmux send-keys    -t "$pane" Enter   2>/dev/null || true
      log "${kind}: tmux /mcp dispatched to pane ${pane}"
    fi
  fi
}

# bash 3.2 (macOS default) has no mapfile — read line by line into array
PIDS=()
while IFS= read -r _pid; do
  [[ -n "$_pid" ]] && PIDS+=("$_pid")
done < <(pgrep -f "$PATTERN" 2>/dev/null || true)

if [[ ${#PIDS[@]} -eq 0 ]]; then
  log "no bun MCP process detected — sending DOWN alert"
  send_alert DOWN "no process"
  exit 2
fi

ORPHANS=()
CHILDREN=()
for pid in "${PIDS[@]}"; do
  [[ -z "$pid" ]] && continue
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
  if [[ "$ppid" == "1" ]]; then
    ORPHANS+=("$pid")
  else
    CHILDREN+=("$pid:$ppid")
  fi
done

if [[ ${#ORPHANS[@]} -gt 0 ]]; then
  for opid in "${ORPHANS[@]}"; do
    kill "$opid" 2>/dev/null && log "killed orphan bun pid=${opid} (PPID=1)" || \
                                log "failed to SIGTERM orphan pid=${opid}"
  done
  if [[ -r "$PID_FILE" ]]; then
    stale=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$stale" ]] && ! kill -0 "$stale" 2>/dev/null; then
      rm -f "$PID_FILE"
      log "removed stale bot.pid (was pid=${stale})"
    fi
  fi
  detail="killed PID(s): ${ORPHANS[*]}"
  send_alert ORPHAN_CLEANED "$detail"
  exit 2
fi

if [[ -f "$STATE_FILE" ]]; then
  rm -f "$STATE_FILE"
  log "recovered — clearing alert state (children: ${CHILDREN[*]})"
fi
exit 0
