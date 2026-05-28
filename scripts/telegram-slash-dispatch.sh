#!/usr/bin/env bash
# Dispatch a slash command into the currently active Claude Code tmux pane.
# Called by the user-prompt-submit hook when a Telegram-origin message starts
# with a whitelisted CLI slash command (/new, /clear, /compact, ...).
#
# Usage: telegram-slash-dispatch.sh "/new"

set -euo pipefail

CMD="${1:?slash command required}"

# Defense in depth: re-validate the argument against the SAME whitelist as
# the hook. This script may be reused by other callers in the future, so it
# must not trust the caller to have validated the input.
case "$CMD" in
  /new|/clear|/compact|/cost|/exit|/login|/logout|/config|/model|/help) ;;
  *)
    echo "telegram-slash-dispatch: refused — '$CMD' is not in the whitelist" >&2
    exit 2
    ;;
esac

# Reject whitespace, control chars, and shell/tmux metacharacters even
# inside the whitelist (the case above already pinned $CMD to a literal
# string, but this is belt-and-suspenders against future whitelist edits).
if [[ "$CMD" =~ [[:space:][:cntrl:]\;\|\&\`\$\(\)\<\>\"\\\'] ]]; then
  echo "telegram-slash-dispatch: refused — '$CMD' contains forbidden characters" >&2
  exit 2
fi

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

# Use -l (literal) so tmux types $CMD character-by-character instead of
# interpreting tmux key names like Enter / C-c / C-d. Send Enter as a
# separate, non-literal send-keys call.
tmux send-keys -l -t "$PANE" "$CMD"
tmux send-keys    -t "$PANE" Enter
echo "telegram-slash-dispatch: sent '$CMD' to pane $PANE" >&2
