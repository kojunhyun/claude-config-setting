#!/usr/bin/env bash
# Dispatch a slash command into the currently active Claude Code tmux pane.
# Called by the user-prompt-submit hook when a Telegram-origin message starts
# with a whitelisted CLI slash command (/new, /clear, /compact, ...).
#
# Usage: telegram-slash-dispatch.sh "/new"

set -euo pipefail

CMD="${1:?slash command required}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "telegram-slash-dispatch: tmux not installed" >&2
  exit 1
fi

# Find a tmux pane whose foreground process looks like Claude Code.
# claude CLI typically appears as 'claude', 'node', 'bun', or 'deno'.
PANE=$(tmux list-panes -a -F '#{pane_id}|#{pane_current_command}|#{pane_active}' 2>/dev/null \
  | awk -F'|' '$2 ~ /^(claude|node|bun|deno)$/ { print $1; exit }')

if [[ -z "${PANE:-}" ]]; then
  echo "telegram-slash-dispatch: no active Claude tmux pane found" >&2
  exit 1
fi

tmux send-keys -t "$PANE" "$CMD" Enter
echo "telegram-slash-dispatch: sent '$CMD' to pane $PANE" >&2
