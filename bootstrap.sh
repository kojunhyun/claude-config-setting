#!/usr/bin/env bash
# Claude Config bootstrap — Linux / macOS / WSL
# Idempotent. Run after `git clone`.
#
# Usage:
#   ./bootstrap.sh              # auto-detect OS, use defaults
#   CLAUDE_CONFIG_DIR=/custom/path ./bootstrap.sh

set -euo pipefail

# ---------- OS detection ----------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[bootstrap] detected OS: $OS"
echo "[bootstrap] config repo:  $SCRIPT_DIR"

# ---------- Per-OS defaults ----------
case "$OS" in
  wsl)
    DEFAULT_CONFIG="/mnt/d/00_Claude_Config"
    DEFAULT_PROJECTS="/mnt/d/00_Project"
    DEFAULT_OBSIDIAN="/mnt/d/obsidian"
    DEFAULT_AGENT_TEAM="/mnt/d/00_Agent_Team"
    SHELL_RC="$HOME/.bashrc"
    ;;
  macos)
    DEFAULT_CONFIG="$HOME/claude-config"
    DEFAULT_PROJECTS="$HOME/Projects"
    DEFAULT_OBSIDIAN="$HOME/Obsidian"
    DEFAULT_AGENT_TEAM="$HOME/Agent_Team"
    SHELL_RC="$HOME/.zshrc"
    ;;
  linux)
    DEFAULT_CONFIG="$HOME/claude-config"
    DEFAULT_PROJECTS="$HOME/Projects"
    DEFAULT_OBSIDIAN="$HOME/Obsidian"
    DEFAULT_AGENT_TEAM="$HOME/Agent_Team"
    SHELL_RC="$HOME/.bashrc"
    ;;
  *)
    echo "[bootstrap] ERROR: unsupported OS"
    exit 1
    ;;
esac

# Allow override via env
: "${CLAUDE_CONFIG_DIR:=$DEFAULT_CONFIG}"
: "${PROJECTS_DIR:=$DEFAULT_PROJECTS}"
: "${OBSIDIAN_DIR:=$DEFAULT_OBSIDIAN}"
: "${AGENT_TEAM_DIR:=$DEFAULT_AGENT_TEAM}"

# If repo lives elsewhere, prefer SCRIPT_DIR
CLAUDE_CONFIG_DIR="$SCRIPT_DIR"

echo "[bootstrap] CLAUDE_CONFIG_DIR = $CLAUDE_CONFIG_DIR"
echo "[bootstrap] PROJECTS_DIR     = $PROJECTS_DIR"
echo "[bootstrap] OBSIDIAN_DIR     = $OBSIDIAN_DIR"
echo "[bootstrap] AGENT_TEAM_DIR   = $AGENT_TEAM_DIR"
echo "[bootstrap] SHELL_RC         = $SHELL_RC"

# ---------- 1. Create work dirs ----------
mkdir -p "$PROJECTS_DIR" "$OBSIDIAN_DIR" "$AGENT_TEAM_DIR" "$HOME/.claude"

# ---------- 2. Symlink ~/.claude/{agents,commands,skills,templates,CLAUDE.md} ----------
link_or_replace() {
  local target="$1" linkpath="$2"
  if [ -L "$linkpath" ]; then
    rm "$linkpath"
  elif [ -e "$linkpath" ]; then
    local backup="${linkpath}.bak-$(date +%s)"
    echo "[bootstrap] backing up existing $linkpath → $backup"
    mv "$linkpath" "$backup"
  fi
  ln -s "$target" "$linkpath"
  echo "[bootstrap] linked $linkpath → $target"
}

for item in agents commands skills templates; do
  link_or_replace "$CLAUDE_CONFIG_DIR/$item" "$HOME/.claude/$item"
done
link_or_replace "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

# ---------- 3. Add env vars to shell rc (if missing) ----------
MARKER="# Claude Code per-machine paths (managed by bootstrap.sh)"
if [ -f "$SHELL_RC" ] && grep -qF "$MARKER" "$SHELL_RC"; then
  echo "[bootstrap] env vars already in $SHELL_RC — skipping"
else
  cat >> "$SHELL_RC" <<EOF

$MARKER
export CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"
export PROJECTS_DIR="$PROJECTS_DIR"
export OBSIDIAN_DIR="$OBSIDIAN_DIR"
export AGENT_TEAM_DIR="$AGENT_TEAM_DIR"
EOF
  echo "[bootstrap] env vars appended to $SHELL_RC"
fi

# ---------- 4. WSL-specific: also setup Windows side ----------
if [ "$OS" = "wsl" ]; then
  echo "[bootstrap] WSL detected — auto-running bootstrap.ps1 for Windows side"
  # Convert /mnt/d/... to D:\... for PowerShell
  WIN_PATH=$(echo "$CLAUDE_CONFIG_DIR" | sed -E 's|^/mnt/([a-z])/|\U\1:\\|; s|/|\\|g')
  PS1="$WIN_PATH\\bootstrap.ps1"
  echo "[bootstrap] invoking: powershell.exe -ExecutionPolicy Bypass -File $PS1"
  powershell.exe -ExecutionPolicy Bypass -File "$PS1" || \
    echo "[bootstrap] WARN: PowerShell run failed — run manually:  $PS1"
fi

# ---------- 5. Final hint ----------
echo ""
echo "[bootstrap] done. Next steps:"
echo "  1. reload shell:  source $SHELL_RC"
echo "  2. install Claude Code if not present:  npm i -g @anthropic-ai/claude-code"
echo "  3. login:  claude login"
echo "  4. MCP auth (per-machine):  in claude run  /mcp"
