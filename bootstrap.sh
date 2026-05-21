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
    DEFAULT_PROJECTS="$HOME/00_Projects"
    DEFAULT_OBSIDIAN="$HOME/obsidian"
    DEFAULT_AGENT_TEAM="$HOME/00_Agent_Team"
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

# ---------- 3. Update env vars in shell rc (replace block if exists) ----------
MARKER="# Claude Code per-machine paths (managed by bootstrap.sh)"
END_MARKER="# /Claude Code per-machine paths"
touch "$SHELL_RC"
# Remove any existing block (between markers)
if grep -qF "$MARKER" "$SHELL_RC"; then
  awk -v m="$MARKER" -v e="$END_MARKER" '
    BEGIN { skip=0 }
    index($0, m) { skip=1; next }
    skip && index($0, e) { skip=0; next }
    !skip { print }
  ' "$SHELL_RC" > "$SHELL_RC.tmp" && mv "$SHELL_RC.tmp" "$SHELL_RC"
  echo "[bootstrap] removed old env vars block from $SHELL_RC"
fi
cat >> "$SHELL_RC" <<EOF

$MARKER
export CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"
export PROJECTS_DIR="$PROJECTS_DIR"
export OBSIDIAN_DIR="$OBSIDIAN_DIR"
export AGENT_TEAM_DIR="$AGENT_TEAM_DIR"
# Auto-source shared + machine-local env files
for _f in "\$CLAUDE_CONFIG_DIR/paths.env" "\$CLAUDE_CONFIG_DIR/paths.local.env"; do
  [ -f "\$_f" ] && { set -a; . "\$_f"; set +a; }
done
unset _f
$END_MARKER
EOF
echo "[bootstrap] env vars written to $SHELL_RC"

# ---------- 3a-2. Auto-init paths.local.env with machine-id ----------
LOCAL_ENV="$CLAUDE_CONFIG_DIR/paths.local.env"
if [ ! -f "$LOCAL_ENV" ]; then
  # Sanitize hostname + user for use as ID
  HN="$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]/-/g')"
  US="$(whoami 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]/-/g')"
  [ -z "$HN" ] && HN="unknown"
  [ -z "$US" ] && US="user"
  DEFAULT_MID="${US}-${HN}"
  cat > "$LOCAL_ENV" <<EOF
# paths.local.env — machine-specific overrides + SECRETS (NOT git tracked)
# bootstrap 이 처음 실행할 때 hostname-user 조합으로 초기화.
# 의미있는 이름으로 자유롭게 수정해도 됨.
#
# ⚠️ 이 파일은 secret token 을 담는다 — 외부 노출 금지.
#    .gitignore 에 등재되어 있으나 백업/스크린샷 시 주의.

# 이 머신의 고유 식별자 (daily-log 파일/Notion 페이지 분리 기준)
CLAUDE_MACHINE_ID=$DEFAULT_MID

# weekly 통합 leader 여부. 메인 머신 1대만 true. 나머지는 빈값 or false.
CLAUDE_WEEKLY_LEADER=

# --- Notion Integration Token (각 워크스페이스별 secret) -----
# 발급 절차: SETUP.md "Notion Integration Token 셋업"
# 1) Notion → Settings → Integrations → "Develop or manage integrations"
# 2) 워크스페이스마다 별도 integration 생성, Internal Integration Secret 복사
# 3) 사용할 부모 페이지에서 ... → Add connections → 해당 integration share
# 4) 아래 변수에 secret 입력 (양쪽 따옴표 권장)
CLAUDE_LOG_NOTION_PERSONAL_TOKEN=
CLAUDE_LOG_NOTION_WORK_TOKEN=
# CLAUDE_LOG_NOTION_DEFAULT_TOKEN=   # 단일 타겟 쓸 때

# --- 머신별 경로 오버라이드 (선택) ---------------------------
# CLAUDE_LOG_OBS_DAILY=
# CLAUDE_LOG_OBS_WEEKLY=
EOF
  echo "[bootstrap] created $LOCAL_ENV with CLAUDE_MACHINE_ID=$DEFAULT_MID"
  echo "[bootstrap]   tip: vi $LOCAL_ENV  to rename or set CLAUDE_WEEKLY_LEADER=true on leader"
else
  echo "[bootstrap] paths.local.env already exists — preserved"
fi

# ---------- 3a-3. SSH key auto-gen + work folder mkdir ----------
# paths.env / paths.local.env 의 GIT_* 변수 기반. 이미 키 있으면 그대로.
if [ -f "$CLAUDE_CONFIG_DIR/paths.env" ]; then
  set -a; . "$CLAUDE_CONFIG_DIR/paths.env"; set +a
  [ -f "$LOCAL_ENV" ] && { set -a; . "$LOCAL_ENV"; set +a; }
fi

# 키 생성 함수
gen_key_if_missing() {
  local kname="$1" email="$2"
  [ -z "$kname" ] && return
  local kpath="$HOME/.ssh/$kname"
  if [ -f "$kpath" ]; then
    echo "[bootstrap] SSH key 이미 있음: $kpath"
  else
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    echo "[bootstrap] SSH key 생성: $kpath (passphrase 없이)"
    ssh-keygen -t ed25519 -C "${email:-$kname}" -f "$kpath" -N "" -q
    echo "[bootstrap]   pub: $(cat "${kpath}.pub")"
  fi
}
gen_key_if_missing "${GIT_PERSONAL_KEY_NAME:-}" "${GIT_PERSONAL_EMAIL:-}"
gen_key_if_missing "${GIT_WORK_KEY_NAME:-}"     "${GIT_WORK_EMAIL:-}"

# 회사 폴더 mkdir (OS 별 자동 감지 fallback)
WORK_DIR="${GIT_WORK_DIR:-}"
if [ -z "$WORK_DIR" ]; then
  case "$OS" in
    wsl)        WORK_DIR="/mnt/d/Aixera" ;;
    macos|linux) WORK_DIR="$HOME/Aixera" ;;
  esac
fi
if [ -n "$WORK_DIR" ] && [ ! -d "$WORK_DIR" ]; then
  mkdir -p "$WORK_DIR"
  echo "[bootstrap] work folder created: $WORK_DIR"
fi

# ---------- 3a-4. Auto-write ~/.gitconfig managed block ----------
# paths.env 의 GIT_* 변수 기반 marker-block 으로 idempotent 작성.
# 기존 사용자 셋업은 marker 밖에 있어 보존됨.
if [ -n "${GIT_PERSONAL_NAME:-}" ] && [ -n "${GIT_PERSONAL_EMAIL:-}" ]; then
  GITCONFIG="$HOME/.gitconfig"
  GIT_MARK_BEGIN="# === Claude Config managed (do not edit between markers) ==="
  GIT_MARK_END="# === /Claude Config managed ==="
  touch "$GITCONFIG"
  if grep -qF "$GIT_MARK_BEGIN" "$GITCONFIG"; then
    awk -v m="$GIT_MARK_BEGIN" -v e="$GIT_MARK_END" '
      BEGIN { skip=0 }
      index($0, m) { skip=1; next }
      skip && index($0, e) { skip=0; next }
      !skip { print }
    ' "$GITCONFIG" > "$GITCONFIG.tmp" && mv "$GITCONFIG.tmp" "$GITCONFIG"
  fi
  WORK_DIR_GIT="${GIT_WORK_DIR:-$WORK_DIR}"
  {
    printf '\n%s\n' "$GIT_MARK_BEGIN"
    echo "[user]"
    echo "    name = ${GIT_PERSONAL_NAME}"
    echo "    email = ${GIT_PERSONAL_EMAIL}"
    if [ -n "${GIT_CREDENTIAL_HELPER:-}" ]; then
      echo "[credential]"
      echo "    helper = ${GIT_CREDENTIAL_HELPER}"
    fi
    if [ -n "${GIT_WORK_EMAIL:-}" ] && [ -n "$WORK_DIR_GIT" ]; then
      echo "[includeIf \"gitdir:${WORK_DIR_GIT}/\"]"
      echo "    path = ~/.gitconfig-work"
    fi
    echo "$GIT_MARK_END"
  } >> "$GITCONFIG"
  echo "[bootstrap] ~/.gitconfig managed block 갱신"

  if [ -n "${GIT_WORK_EMAIL:-}" ]; then
    cat > "$HOME/.gitconfig-work" <<EOF
# Claude Config managed — sourced via ~/.gitconfig includeIf
# Do not edit manually; bootstrap 재실행으로 갱신.
[user]
    email = ${GIT_WORK_EMAIL}
EOF
    echo "[bootstrap] ~/.gitconfig-work 작성 (회사 email override)"
  fi
fi

# ---------- 3a-5. Auto-write ~/.ssh/config managed block ----------
if [ -n "${GIT_PERSONAL_HOSTS:-}${GIT_WORK_HOSTS:-}" ]; then
  SSH_CONFIG="$HOME/.ssh/config"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$SSH_CONFIG"; chmod 600 "$SSH_CONFIG"
  SSH_MARK_BEGIN="# === Claude Config managed (do not edit between markers) ==="
  SSH_MARK_END="# === /Claude Config managed ==="
  if grep -qF "$SSH_MARK_BEGIN" "$SSH_CONFIG"; then
    awk -v m="$SSH_MARK_BEGIN" -v e="$SSH_MARK_END" '
      BEGIN { skip=0 }
      index($0, m) { skip=1; next }
      skip && index($0, e) { skip=0; next }
      !skip { print }
    ' "$SSH_CONFIG" > "$SSH_CONFIG.tmp" && mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
  fi
  {
    printf '\n%s\n' "$SSH_MARK_BEGIN"
    if [ -n "${GIT_PERSONAL_HOSTS:-}" ] && [ -n "${GIT_PERSONAL_KEY_NAME:-}" ]; then
      for h in $(echo "$GIT_PERSONAL_HOSTS" | tr ',' ' '); do
        echo "Host $h"
        echo "    HostName $h"
        echo "    User git"
        echo "    IdentityFile ~/.ssh/${GIT_PERSONAL_KEY_NAME}"
        echo "    IdentitiesOnly yes"
        echo
      done
    fi
    if [ -n "${GIT_WORK_HOSTS:-}" ] && [ -n "${GIT_WORK_KEY_NAME:-}" ]; then
      for h in $(echo "$GIT_WORK_HOSTS" | tr ',' ' '); do
        echo "Host $h"
        echo "    HostName $h"
        echo "    User git"
        echo "    IdentityFile ~/.ssh/${GIT_WORK_KEY_NAME}"
        echo "    IdentitiesOnly yes"
        echo
      done
    fi
    echo "$SSH_MARK_END"
  } >> "$SSH_CONFIG"
  echo "[bootstrap] ~/.ssh/config managed block 갱신"
fi

# ---------- 3a-6. Auto-write crontab managed block ----------
if [ "${BOOTSTRAP_AUTO_CRONTAB:-true}" = "true" ] && command -v crontab >/dev/null 2>&1; then
  mkdir -p "$HOME/.claude/logs"
  CRON_MARK_BEGIN="# === Claude Config managed (do not edit between markers) ==="
  CRON_MARK_END="# === /Claude Config managed ==="

  existing_cron=$(crontab -l 2>/dev/null || true)
  filtered_cron=$(printf '%s\n' "$existing_cron" | awk -v m="$CRON_MARK_BEGIN" -v e="$CRON_MARK_END" '
    BEGIN { skip=0 }
    index($0, m) { skip=1; next }
    skip && index($0, e) { skip=0; next }
    !skip { print }
  ')

  CRON_BLOCK="
$CRON_MARK_BEGIN
# 매시간 :05  config push
5 * * * * /usr/bin/env bash -lc 'source ~/.bashrc && claude -p \"/config-push\"' >> $HOME/.claude/logs/push.log 2>&1
# 매일 07:30 config pull
30 7 * * * /usr/bin/env bash -lc 'source ~/.bashrc && claude -p \"/config-sync\"' >> $HOME/.claude/logs/sync.log 2>&1
# 매일 22:00 daily raw
0 22 * * * /usr/bin/env bash -lc 'source ~/.bashrc && claude -p \"/daily-log\"' >> $HOME/.claude/logs/daily.log 2>&1"

  case "${CLAUDE_WEEKLY_LEADER:-}" in
    true|1|yes|y)
      CRON_BLOCK="$CRON_BLOCK
# Leader: 매일 23:00 일일 통합
0 23 * * * /usr/bin/env bash -lc 'source ~/.bashrc && claude -p \"/daily-log-aggregate\"' >> $HOME/.claude/logs/aggregate.log 2>&1
# Leader: 매주 목 12:30 주간 통합
30 12 * * 4 /usr/bin/env bash -lc 'source ~/.bashrc && claude -p \"/weekly-log\"' >> $HOME/.claude/logs/weekly.log 2>&1"
      echo "[bootstrap] crontab — leader 머신용 5개 routine 등록"
      ;;
    *)
      echo "[bootstrap] crontab — non-leader 3개 routine 등록"
      ;;
  esac

  CRON_BLOCK="$CRON_BLOCK
$CRON_MARK_END"

  printf '%s\n%s\n' "$filtered_cron" "$CRON_BLOCK" | crontab -
fi

# ---------- 3b. Enable git hooks (post-merge auto-sync) ----------
if [ -d "$CLAUDE_CONFIG_DIR/.git" ] && [ -d "$CLAUDE_CONFIG_DIR/hooks" ]; then
  ( cd "$CLAUDE_CONFIG_DIR" && git config core.hooksPath hooks )
  chmod +x "$CLAUDE_CONFIG_DIR/hooks/"* 2>/dev/null || true
  echo "[bootstrap] git hooks enabled (core.hooksPath = hooks)"
fi

# ---------- 3c. Install plugins from plugins.manifest ----------
MANIFEST="$CLAUDE_CONFIG_DIR/plugins.manifest"
if [ -f "$MANIFEST" ]; then
  if command -v claude >/dev/null 2>&1; then
    echo "[bootstrap] syncing plugins from $MANIFEST"
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
      # strip CR, leading/trailing whitespace
      line="${raw_line%$'\r'}"
      line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac

      action="$(echo "$line" | awk '{print $1}')"
      arg="$(echo "$line" | awk '{print $2}')"
      [ -z "$arg" ] && continue

      case "$action" in
        market)
          echo "[bootstrap]   market add: $arg"
          claude plugin marketplace add "$arg" 2>&1 | sed 's/^/[bootstrap]     /' || \
            echo "[bootstrap]     WARN: marketplace add failed: $arg (may already exist)"
          ;;
        plugin)
          echo "[bootstrap]   plugin install: $arg"
          claude plugin install "$arg" 2>&1 | sed 's/^/[bootstrap]     /' || \
            echo "[bootstrap]     WARN: install failed: $arg (may already be installed)"
          ;;
        *)
          echo "[bootstrap]   WARN: unknown manifest action '$action' — skipped"
          ;;
      esac
    done < "$MANIFEST"
    echo "[bootstrap] plugin sync done. Run 'claude plugin list' to verify."
  else
    echo "[bootstrap] SKIP: 'claude' CLI not found — install it first, then re-run bootstrap"
    echo "[bootstrap]       (or run /sync-plugins inside Claude Code later)"
  fi
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
