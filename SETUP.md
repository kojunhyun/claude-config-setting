# Claude Config — Multi-Machine Setup

Canonical repo for `~/.claude/{agents,commands,skills,templates}` + `CLAUDE.md`.

Sync via git. Per-machine paths via env vars. Bootstrap scripts auto-detect OS.

---

## OS별 사용 시나리오

| Case | OS | 동기화 방식 | 스크립트 |
|---|---|---|---|
| 1 | Windows 단독 | git pull → bootstrap.ps1 | `bootstrap.ps1` |
| 2 | Windows + WSL | bootstrap.sh가 PS1 자동 호출 | `bootstrap.sh` |
| 3 | Linux 단독 | git pull → bootstrap.sh | `bootstrap.sh` |
| 4 | macOS (앱 + CLI) | git pull → bootstrap.sh | `bootstrap.sh` |

---

## Case 1 — Windows 만

```powershell
# 1. clone
git clone git@github.com:고준현/claude-config.git D:\00_Claude_Config

# 2. bootstrap
cd D:\00_Claude_Config
.\bootstrap.ps1

# 3. PowerShell 재시작 → Claude Code 설치/로그인
npm i -g @anthropic-ai/claude-code
claude login
```

생성되는 것:
- `C:\Users\<user>\.claude\{agents,commands,skills,templates}` → junction → repo
- `C:\Users\<user>\.claude\CLAUDE.md` → copy (또는 symlink, Dev Mode 있으면)
- PowerShell `$PROFILE` + User-scope env vars

---

## Case 2 — Windows + WSL

WSL에서 한 번 실행. WSL 쪽 + Windows 쪽 모두 자동 셋팅됨.

```bash
# WSL Ubuntu
git clone git@github.com:고준현/claude-config.git /mnt/d/00_Claude_Config
cd /mnt/d/00_Claude_Config
./bootstrap.sh
```

내부에서:
1. WSL `~/.claude/*` 심볼릭링크 → repo
2. `~/.bashrc` 에 env vars 추가
3. **자동으로** `powershell.exe bootstrap.ps1` 호출 → Windows 측 셋업

두 OS 가 같은 D: 디스크 공유. 한쪽에서 git pull 하면 양쪽 즉시 반영.

---

## Case 3 — Linux 단독 (Ubuntu/Debian/etc.)

```bash
# 1. clone (HOME에 두는 게 표준)
git clone git@github.com:고준현/claude-config.git ~/claude-config

# 2. bootstrap
cd ~/claude-config
./bootstrap.sh

# 3. shell 재시작 후
npm i -g @anthropic-ai/claude-code
claude login
```

생성되는 것:
- `~/.claude/*` 심볼릭링크 → repo
- `~/.bashrc` 에 env vars (`PROJECTS_DIR=$HOME/Projects` 등 HOME 기준)

---

## Case 4 — macOS (Claude Desktop App + CLI)

```bash
# 1. clone
git clone git@github.com:고준현/claude-config.git ~/claude-config

# 2. bootstrap (zsh 자동 감지)
cd ~/claude-config
./bootstrap.sh

# 3. CLI 설치
npm i -g @anthropic-ai/claude-code
claude login

# 4. Desktop app 도 같은 ~/.claude/ 읽음 — 별도 셋팅 불필요
```

데스크탑 앱과 CLI 가 같은 config dir 공유. `/develop` 등 명령어 둘 다에서 동작.

---

## Env Vars 표

| Var | Win | WSL | Linux | macOS |
|---|---|---|---|---|
| `CLAUDE_CONFIG_DIR` | `D:\00_Claude_Config` | `/mnt/d/00_Claude_Config` | `~/claude-config` | `~/claude-config` |
| `PROJECTS_DIR` | `D:\00_Project` | `/mnt/d/00_Project` | `~/Projects` | `~/Projects` |
| `OBSIDIAN_DIR` | `D:\obsidian` | `/mnt/d/obsidian` | `~/Obsidian` | `~/Obsidian` |
| `AGENT_TEAM_DIR` | `D:\00_Agent_Team` | `/mnt/d/00_Agent_Team` | `~/Agent_Team` | `~/Agent_Team` |

값 커스텀하려면 스크립트 실행 전 env 로 override:

```bash
PROJECTS_DIR=/custom/path ./bootstrap.sh
```

```powershell
.\bootstrap.ps1 -ProjectsDir 'E:\MyProjects'
```

---

## 일상 워크플로

**변경 적용:**
```bash
cd $CLAUDE_CONFIG_DIR
# edit ...
git add . && git commit -m "feat: ..."
git push
```

**다른 머신에서 받기:**
```bash
cd $CLAUDE_CONFIG_DIR
git pull
./bootstrap.sh    # (or bootstrap.ps1 on Windows-only)
                  # CLAUDE.md copy 갱신 + 새 symlink 보정
```

---

## .gitignore 정책

추적 OK:
- `agents/`, `commands/`, `skills/`, `templates/`
- `CLAUDE.md`, `settings.json`, `SETUP.md`, `bootstrap.*`

추적 NO (per-machine 또는 secret):
- `settings.local.json`, `.credentials.json`
- `cache/`, `sessions/`, `projects/`, `history.jsonl` 등 런타임 상태

---

## 트러블슈팅

| 증상 | 해결 |
|---|---|
| `/develop` 등 안 보임 | Claude Code 재시작 → 그래도 없으면 `~/.claude/commands/` 심볼릭링크 확인 |
| Win CLAUDE.md 안 바뀜 | Developer Mode 켜고 bootstrap.ps1 재실행 (symlink 생성) 또는 `git pull` 후 ps1 재실행 (copy 갱신) |
| env vars 안 먹음 | shell 재시작. WSL은 `source ~/.bashrc`, Win은 새 PowerShell 창 |
| Mac에서 path 못 찾음 | `echo $PROJECTS_DIR` 로 확인. 없으면 `~/.zshrc` 직접 편집 |
| junction 실패 (Win) | 대상 폴더가 이미 다른 junction일 수 있음. 수동 `rmdir`로 제거 후 재실행 |
