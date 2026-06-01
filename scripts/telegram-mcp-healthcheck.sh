#!/usr/bin/env bash
# Telegram MCP healthcheck — runs every 2 min via launchd (macOS) / cron (Linux).
# If the plugin's polling process is dead, send a recovery notice via direct
# Telegram Bot API (bypassing the dead MCP) and best-effort send `/mcp` to any
# active Claude Code tmux pane so reconnect is one keystroke away.
#
# Exit codes:
#   0 — healthy, or down but already alerted within suppression window
#   2 — down and alert dispatched
set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
STATE_DIR="${HOME}/.claude/state"
LOG_FILE="${LOG_DIR}/telegram-mcp-healthcheck.log"
STATE_FILE="${STATE_DIR}/telegram-mcp-last-alert"
ENV_FILE="${HOME}/.claude/channels/telegram/.env"
ACCESS_FILE="${HOME}/.claude/channels/telegram/access.json"
SUPPRESS_SEC=1800   # one alert per 30 min while still down

mkdir -p "$LOG_DIR" "$STATE_DIR"

log() {
  printf '%s [healthcheck] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >> "$LOG_FILE"
}

# Detect the telegram plugin polling process. Matches both:
#   bun run --cwd .../plugins/cache/.../telegram/0.0.6 ...
#   node/bun running .../telegram/.../server.ts
if pgrep -f 'telegram/0\.[0-9]+\.[0-9]+.*server\.ts|--cwd[= ].*telegram/0\.[0-9]+\.[0-9]+' >/dev/null 2>&1; then
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    log "recovered — clearing alert state"
  fi
  exit 0
fi

NOW=$(date +%s)
if [[ -f "$STATE_FILE" ]]; then
  LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  if (( NOW - LAST < SUPPRESS_SEC )); then
    log "still down, alert suppressed (last=${LAST}, now=${NOW})"
    exit 0
  fi
fi

log "telegram MCP process not detected — dispatching alert"
echo "$NOW" > "$STATE_FILE"

if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

HOST="$(hostname -s 2>/dev/null || uname -n)"
TIMESTAMP="$(date '+%H:%M')"
MSG="📡 텔레그램 MCP 가 ${HOST} 에서 응답하지 않습니다 (${TIMESTAMP}). Claude Code 에서 /mcp 로 재연결해주세요."

CHAT_ID=""
if [[ -r "$ACCESS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  CHAT_ID=$(jq -r '.allowFrom[0] // empty' "$ACCESS_FILE" 2>/dev/null || true)
fi

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "$CHAT_ID" ]]; then
  if curl -s -m 10 -X POST \
       "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
       --data-urlencode "chat_id=${CHAT_ID}" \
       --data-urlencode "text=${MSG}" >/dev/null 2>&1; then
    log "recovery notice sent via direct API to chat_id=${CHAT_ID}"
  else
    log "direct API send failed (network or token issue)"
  fi
else
  log "direct API skipped (token=${TELEGRAM_BOT_TOKEN:+present} chat_id=${CHAT_ID:-empty})"
fi

# Best-effort: surface /mcp in the active Claude tmux pane (one-keystroke reconnect)
if command -v tmux >/dev/null 2>&1; then
  PANE=$(tmux list-panes -a -F '#{pane_id}|#{pane_current_command}' 2>/dev/null \
    | awk -F'|' '$2 ~ /^(claude|node|bun|deno)$/ { print $1; exit }' || true)
  if [[ -n "${PANE:-}" ]]; then
    tmux send-keys -l -t "$PANE" "/mcp" 2>/dev/null || true
    tmux send-keys    -t "$PANE" Enter   2>/dev/null || true
    log "tmux: /mcp dispatched to pane ${PANE}"
  else
    log "tmux: no active Claude pane (skipped /mcp dispatch)"
  fi
fi

exit 2
