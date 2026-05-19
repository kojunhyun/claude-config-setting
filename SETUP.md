# Claude Config — Multi-Machine Setup

Canonical repo for `~/.claude/{agents,commands,skills,templates}` + `CLAUDE.md`.

Sync via git. Per-machine paths via env vars.

---

## Env Vars (set in shell rc)

Set these on every machine before using Claude Code:

| Var | Purpose | Example |
|---|---|---|
| `CLAUDE_CONFIG_DIR` | This repo clone | `/mnt/d/00_Claude_Config` / `~/claude-config` |
| `PROJECTS_DIR` | `/develop` output | `/mnt/d/00_Project` / `~/Projects` |
| `OBSIDIAN_DIR` | Obsidian vault | `/mnt/d/obsidian` / `~/Obsidian` |
| `AGENT_TEAM_DIR` | agent team memory | `/mnt/d/00_Agent_Team` / `~/Agent_Team` |

---

## Bootstrap — WSL Ubuntu (current setup)

`~/.bashrc` 추가:
```bash
export CLAUDE_CONFIG_DIR=/mnt/d/00_Claude_Config
export PROJECTS_DIR=/mnt/d/00_Project
export OBSIDIAN_DIR=/mnt/d/obsidian
export AGENT_TEAM_DIR=/mnt/d/00_Agent_Team
```

이미 심볼릭링크 생성 완료. `git pull` 만 하면 동기화.

---

## Bootstrap — Windows (current setup)

PowerShell `$PROFILE` 추가:
```powershell
$env:CLAUDE_CONFIG_DIR = "D:\00_Claude_Config"
$env:PROJECTS_DIR      = "D:\00_Project"
$env:OBSIDIAN_DIR      = "D:\obsidian"
$env:AGENT_TEAM_DIR    = "D:\00_Agent_Team"
```

`C:\Users\고준현\.claude\` 에 junction 생성됨:
- `agents`, `commands`, `skills`, `templates` → `D:\00_Claude_Config\*` (junction)
- `CLAUDE.md` → 일반 copy (admin 권한 없어 symlink 실패)

**CLAUDE.md 업데이트 시:** `git pull` 후 PowerShell에서
```powershell
Copy-Item D:\00_Claude_Config\CLAUDE.md "$env:USERPROFILE\.claude\CLAUDE.md" -Force
```

(또는 Developer Mode 켜고 symlink 생성하면 자동 동기화)

---

## Bootstrap — Mac mini (신규)

1. **GitHub 에 push 후 clone**
   ```bash
   # Windows/WSL 에서 (먼저)
   cd /mnt/d/00_Claude_Config
   git remote add origin git@github.com:고준현/claude-config.git
   git push -u origin main

   # Mac 에서
   git clone git@github.com:고준현/claude-config.git ~/claude-config
   ```

2. **`~/.zshrc` 추가**
   ```bash
   export CLAUDE_CONFIG_DIR=$HOME/claude-config
   export PROJECTS_DIR=$HOME/Projects
   export OBSIDIAN_DIR=$HOME/Obsidian
   export AGENT_TEAM_DIR=$HOME/Agent_Team
   mkdir -p $PROJECTS_DIR $OBSIDIAN_DIR $AGENT_TEAM_DIR
   ```

3. **`~/.claude/` 심볼릭링크 생성**
   ```bash
   mkdir -p ~/.claude
   cd ~/.claude
   ln -s $CLAUDE_CONFIG_DIR/agents    agents
   ln -s $CLAUDE_CONFIG_DIR/commands  commands
   ln -s $CLAUDE_CONFIG_DIR/skills    skills
   ln -s $CLAUDE_CONFIG_DIR/templates templates
   ln -s $CLAUDE_CONFIG_DIR/CLAUDE.md CLAUDE.md
   ```

4. **Claude Code 설치 + 로그인**
   ```bash
   npm i -g @anthropic-ai/claude-code
   claude login
   ```

5. **MCP 서버 인증 (재인증 필요)**
   - `claude` 실행 후 `/mcp`
   - notion, figma 등 각각 OAuth 재인증

---

## 일상 워크플로

**변경 적용 (예: 새 skill 추가):**
```bash
# 어느 머신에서든
cd $CLAUDE_CONFIG_DIR
# 편집...
git add . && git commit -m "feat: add new skill"
git push
```

**다른 머신에서 받기:**
```bash
cd $CLAUDE_CONFIG_DIR
git pull
# Windows: CLAUDE.md 수동 copy (위 참조)
```

---

## .gitignore 정책

추적 OK:
- `agents/`, `commands/`, `skills/`, `templates/`
- `CLAUDE.md`, `settings.json`, `SETUP.md`

추적 NO (per-machine 또는 secret):
- `settings.local.json`, `.credentials.json`
- `cache/`, `sessions/`, `projects/`, `history.jsonl` 등 런타임 상태

---

## 트러블슈팅

**`/develop` 등 명령 안 보임:** Claude Code 재시작. 그래도 없으면 `~/.claude/commands/` 심볼릭링크 확인.

**Windows CLAUDE.md 안 바뀜:** symlink 아닌 copy. `git pull` 후 수동 copy 또는 Developer Mode 켜고 symlink 재생성.

**Mac 에서 path 변수 미설정:** SKILL.md 가 `$PROJECTS_DIR` 같은 env var 참조. shell rc 에 export 되어 있는지 확인.
