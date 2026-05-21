# Claude Config — Multi-Machine Setup

`~/.claude/{agents,commands,skills,templates}` + `CLAUDE.md` 를 git 한 곳에서 관리하고
머신마다 심볼릭링크로 연결한다. bootstrap 스크립트가 OS 를 자동 감지해 셋업을 끝낸다.

> 깊이있는 운영 가이드(스케줄링·Notion·트러블슈팅 전부)는 [`SETUP.md`](./SETUP.md) 참고.
> 이 문서는 **새 머신에서 5분 안에 동작시키는 것** 만 목표로 한다.

---

## TL;DR — OS별 한 줄

| OS | Clone 위치 | Bootstrap |
|---|---|---|
| **macOS** | `~/claude-config` | `./bootstrap.sh` |
| **Linux** | `~/claude-config` | `./bootstrap.sh` |
| **WSL (+ Windows)** | `/mnt/d/00_Claude_Config` | `./bootstrap.sh` (Windows 측도 자동) |
| **Windows 단독** | `D:\00_Claude_Config` | `.\bootstrap.ps1` |

bootstrap 은 **idempotent**. 언제든 다시 돌려도 안전하다.

---

## 공통 사전 준비 (모든 OS)

1. **git** 설치
2. **Node.js LTS** 설치 (`claude` CLI 가 npm 패키지)
3. **SSH key** 가 GitHub 에 등록돼 있을 것 (없으면 bootstrap 이 생성, 등록은 수동)

---

## macOS

### 1) Clone & Bootstrap

```bash
git clone git@github.com:kojunhyun/claude-config-setting.git ~/claude-config
cd ~/claude-config
chmod +x bootstrap.sh
./bootstrap.sh
```

bootstrap 이 하는 일:
- `~/.claude/{agents,commands,skills,templates,CLAUDE.md}` → repo 심볼릭링크
- `~/.zshrc` 에 env vars block 자동 삽입 (idempotent)
- 작업 폴더 자동 생성: `~/00_Projects`, `~/obsidian`, `~/00_Agent_Team`
- `paths.local.env` 초기 생성 + `CLAUDE_MACHINE_ID` 디폴트 (`<user>-<host>`)
- SSH key 없으면 ed25519 생성
- `plugins.manifest` 의 플러그인 자동 설치

### 2) Claude CLI

```bash
npm i -g @anthropic-ai/claude-code
claude login
```

Claude Desktop App 도 같은 `~/.claude/` 를 읽으므로 별도 셋팅 불필요.

### 3) 셸 재시작 → 검증

```zsh
source ~/.zshrc
claude
> /setup-status
```

> macOS 기본 경로 커스텀:
> ```bash
> PROJECTS_DIR=~/Code OBSIDIAN_DIR=~/Notes ./bootstrap.sh
> ```

---

## Linux (Ubuntu / Debian / Fedora 등)

### 1) Clone & Bootstrap

```bash
git clone git@github.com:kojunhyun/claude-config-setting.git ~/claude-config
cd ~/claude-config
chmod +x bootstrap.sh
./bootstrap.sh
```

기본 경로: `~/Projects`, `~/Obsidian`, `~/Agent_Team`. `~/.bashrc` 에 env block 추가.

### 2) Claude CLI

```bash
npm i -g @anthropic-ai/claude-code
claude login
```

### 3) 검증

```bash
source ~/.bashrc
claude
> /setup-status
```

---

## WSL + Windows (가장 권장 — 한 번에 두 OS)

WSL Ubuntu 안에서 한 번만 실행하면 **WSL 쪽 + Windows 쪽 둘 다** 셋업된다.
두 OS 가 같은 D: 디스크를 공유하므로 git pull 한 번에 양쪽이 즉시 반영.

### 1) WSL 안에서 clone

```bash
git clone git@github.com:kojunhyun/claude-config-setting.git /mnt/d/00_Claude_Config
cd /mnt/d/00_Claude_Config
chmod +x bootstrap.sh
./bootstrap.sh
```

자동으로 일어나는 일:
1. WSL `~/.claude/*` → `/mnt/d/00_Claude_Config/*` 심볼릭링크
2. `~/.bashrc` 에 env vars
3. **`powershell.exe -File bootstrap.ps1` 자동 호출** → Windows 측 셋업
   - `C:\Users\<user>\.claude\*` → repo junction
   - Windows User-scope env vars
   - PowerShell `$PROFILE` 에 paths.env auto-source

### 2) Claude CLI (WSL + Windows 각각)

```bash
# WSL
npm i -g @anthropic-ai/claude-code && claude login
```

```powershell
# Windows PowerShell
npm i -g @anthropic-ai/claude-code
claude login
```

### 3) 검증

```bash
source ~/.bashrc
claude
> /setup-status
```

---

## Windows 단독 (WSL 없이)

### 1) Clone & Bootstrap

```powershell
# PowerShell (관리자 권한 불필요)
git clone git@github.com:kojunhyun/claude-config-setting.git D:\00_Claude_Config
cd D:\00_Claude_Config
.\bootstrap.ps1
```

bootstrap.ps1 이 하는 일:
- `C:\Users\<user>\.claude\{agents,commands,skills,templates}` → `mklink /J` junction
- `CLAUDE.md` 는 copy (Developer Mode 켜져있으면 symlink)
- User-scope env vars (`CLAUDE_CONFIG_DIR`, `PROJECTS_DIR`, `OBSIDIAN_DIR`, `AGENT_TEAM_DIR`)
- PowerShell `$PROFILE` 에 paths.env auto-source

### 2) Claude CLI

```powershell
npm i -g @anthropic-ai/claude-code
claude login
```

### 3) PowerShell 재시작 → 검증

```powershell
claude
> /setup-status
```

> 경로 커스텀:
> ```powershell
> .\bootstrap.ps1 -ProjectsDir 'E:\MyProjects' -ObsidianDir 'E:\Notes'
> ```

---

## OS별 기본 경로 한눈에

| Env Var | macOS | Linux | WSL | Windows |
|---|---|---|---|---|
| `CLAUDE_CONFIG_DIR` | `~/claude-config` | `~/claude-config` | `/mnt/d/00_Claude_Config` | `D:\00_Claude_Config` |
| `PROJECTS_DIR` | `~/00_Projects` | `~/Projects` | `/mnt/d/00_Project` | `D:\00_Project` |
| `OBSIDIAN_DIR` | `~/obsidian` | `~/Obsidian` | `/mnt/d/obsidian` | `D:\obsidian` |
| `AGENT_TEAM_DIR` | `~/00_Agent_Team` | `~/Agent_Team` | `/mnt/d/00_Agent_Team` | `D:\00_Agent_Team` |
| Shell RC | `~/.zshrc` | `~/.bashrc` | `~/.bashrc` | `$PROFILE` |

---

## Bootstrap 직후 — 사람이 한 번만 하는 일

bootstrap 은 자동화 가능한 것까지만 한다. 다음은 새 머신마다 사람이 직접:

1. **`paths.local.env` 채우기** (gitignored, secret)
   ```bash
   $EDITOR $CLAUDE_CONFIG_DIR/paths.local.env
   ```
   - `CLAUDE_MACHINE_ID` 의미있게 (예: `jhko-mac-mini`)
   - `CLAUDE_WEEKLY_LEADER=true` — **메인 머신 1대만**
   - `CLAUDE_LOG_NOTION_PERSONAL_TOKEN` / `_WORK_TOKEN` (선택)

2. **GitHub 에 공개키 등록** (SSH 신규 생성된 경우)
   ```bash
   cat ~/.ssh/id_ed25519.pub   # 복사 → github.com Settings → SSH keys
   ```

3. **검증**
   ```bash
   claude
   > /setup-status            # ⏳ 표시된 항목 차례로 처리
   ```

---

## 일상 워크플로

### 변경 push (작업한 머신에서)

```bash
cd $CLAUDE_CONFIG_DIR
# skills/, agents/, commands/ 등 편집
git add . && git commit -m "feat: ..."
git push
```

또는 `claude /config-push` — 자동 secret scan + commit + push.

### 변경 pull (다른 머신에서)

```bash
cd $CLAUDE_CONFIG_DIR
git pull           # post-merge hook 이 변경 사항 요약 출력
```

또는 `claude /config-sync` — 안전한 rebase + 변경 요약 + 재시작 안내.

신규 `skills/`, `agents/`, `commands/` 인식하려면 **Claude Code 재시작** 필요.

---

## 다른 위치로 옮기기

bootstrap 은 **자기 위치를 기준**으로 동작한다. 옮긴 후 한 번만 다시:

```bash
mv /mnt/d/00_Claude_Config /mnt/e/MyClaude
cd /mnt/e/MyClaude
./bootstrap.sh        # symlink/junction/env vars 모두 갱신
```

---

## 트러블슈팅 (최소판)

| 증상 | 해결 |
|---|---|
| `claude: command not found` | `npm i -g @anthropic-ai/claude-code` 먼저, 그 후 bootstrap 재실행 |
| `/develop` 등 명령 안 보임 | Claude Code 재시작. 안 되면 `ls -la ~/.claude/commands` 로 심볼릭링크 확인 |
| env vars 안 먹음 | shell 재시작 (WSL: `source ~/.bashrc`, Win: 새 PowerShell 창) |
| Windows `CLAUDE.md` 안 바뀜 | Developer Mode 켜고 `.\bootstrap.ps1` 재실행 (symlink), 아니면 `git pull` 후 ps1 재실행 (copy 갱신) |
| WSL 에서 `.\bootstrap.ps1` 안 돌아감 | `bootstrap.sh` 안에서 자동 호출됨. WSL 쪽 한 번만 돌리면 됨 |
| junction 실패 (Win) | 대상 폴더가 이미 다른 junction. `rmdir <link>` 후 ps1 재실행 |
| Permission denied (bootstrap.sh) | `chmod +x bootstrap.sh` 한 번 |

더 깊은 트러블슈팅 / 멀티머신 정책 / Notion 셋업 / 스케줄링은 [`SETUP.md`](./SETUP.md).

---

## 디렉토리 구조

```
$CLAUDE_CONFIG_DIR/
├── README.md            ← 지금 이 파일 (OS별 빠른 시작)
├── SETUP.md             ← 깊이있는 운영 가이드
├── CLAUDE.md            ← Arch orchestrator 시스템 프롬프트
├── bootstrap.sh         ← Linux / macOS / WSL
├── bootstrap.ps1        ← Windows
├── paths.env            ← git tracked, 공통 정책
├── paths.local.env      ← gitignored, 머신별 secret/ID  (bootstrap 이 생성)
├── plugins.manifest     ← 플러그인 선언적 목록
├── settings.json        ← Claude Code 전역 설정
├── agents/              ← Arch 의 8개 lead + 추가 subagent
├── commands/            ← `/daily-log`, `/setup-status` 등 슬래시 명령
├── skills/              ← 명령 본체 로직
├── templates/           ← 새 프로젝트 부트스트랩용 템플릿
└── hooks/               ← git post-merge 등
```
