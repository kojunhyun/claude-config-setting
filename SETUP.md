# Claude Config — Multi-Machine Setup

Canonical repo for `~/.claude/{agents,commands,skills,templates}` + `CLAUDE.md`.

Sync via git. Per-machine paths via env vars. Bootstrap scripts auto-detect OS.

---

## 머신 간 스킬/Agent 동기화 모델

한 머신에서 스킬/agent/command 수정 → git push → **다른 머신들이 어떻게 받나**.

### 동기화 체인

```
머신 A 에서 수정                 머신 B 에서 받기
────────────────                 ────────────────
edit skills/foo/SKILL.md
git commit + push  ───── push ──►  origin/main
                                       │
                                       │ git pull (3가지 방법 중 하나)
                                       ▼
                                   $CLAUDE_CONFIG_DIR/skills/foo/SKILL.md
                                       │ symlink
                                       ▼
                                   ~/.claude/skills/foo/SKILL.md
                                       │
                                       │ Claude Code 재시작
                                       ▼
                                   머신 B 의 Claude Code 가 새 스킬 인식
```

### ⚠️ 멀티머신 스케줄 — 시스템 cron 권장

`claude.ai /schedule` (routine) 은 **사용자 계정 기반**이라 한 머신에서 등록하면
다른 머신에서도 트리거될 수 있다 (정책상 동작이 명확하지 않고 변경될 수 있음).
모든 머신이 동시에 동일 routine 을 돌리면 충돌 / 자원 낭비 위험.

**권장: 시스템 cron + skill 머신 가드 이중 보호**

#### 1. 시스템 cron — 머신 격리 자연 보장

각 머신의 OS cron 에 직접 등록. 그 머신 외에서는 절대 안 돔.

```cron
# === Mac mini (leader) — 모든 routine ===
5   *   * * *  cd $HOME/claude-config && claude -p "/config-push"          >> ~/.claude/logs/push.log      2>&1
30  7   * * *  cd $HOME/claude-config && claude -p "/config-sync"          >> ~/.claude/logs/sync.log      2>&1
0   22  * * *  cd $HOME/claude-config && claude -p "/daily-log"            >> ~/.claude/logs/daily.log     2>&1
0   23  * * *  cd $HOME/claude-config && claude -p "/daily-log-aggregate"  >> ~/.claude/logs/aggregate.log 2>&1
30  12  * * 4  cd $HOME/claude-config && claude -p "/weekly-log"           >> ~/.claude/logs/weekly.log    2>&1

# === WSL desktop / Ubuntu (non-leader) — 자기 작업만 ===
5   *   * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-push"  >> ~/.claude/logs/push.log  2>&1
30  7   * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-sync"  >> ~/.claude/logs/sync.log  2>&1
0   22  * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/daily-log"    >> ~/.claude/logs/daily.log 2>&1
```

```powershell
# Windows Task Scheduler
schtasks /Create /TN "ClaudePush" /SC HOURLY /MO 1 /ST 00:05 /TR "claude -p /config-push"
schtasks /Create /TN "ClaudeSync" /SC DAILY  /ST 07:30 /TR "claude -p /config-sync"
schtasks /Create /TN "ClaudeDaily" /SC DAILY /ST 22:00 /TR "claude -p /daily-log"
```

`crontab -e` 로 직접 편집.

#### 2. Skill 머신 가드 — paths.env 정책

system cron 외에 `/schedule` 또는 수동 호출까지도 차단하려면 paths.env 에:

```env
# 메인 머신만 자동 push (다른 머신 작업도 git pull 로 동기화 후 push 가능)
SCHEDULE_PUSH_MACHINES="jhko-mac-mini"

# 모든 머신이 pull (일반적, 빈값 권장)
SCHEDULE_SYNC_MACHINES=""

# 모든 머신이 자기 raw 작성 (빈값 권장)
SCHEDULE_DAILY_MACHINES=""
```

각 skill 의 Stage 0 가 `CLAUDE_MACHINE_ID` 보고 매칭 안 되면 즉시 `exit 0`.
**시스템 cron 으로 호출되든 `/schedule` 로 호출되든 동일 차단**.

#### 3. 이중 보호의 의미

| 레이어 | 차단 시점 | 보호 범위 |
|---|---|---|
| 시스템 cron | OS 수준 — 등록 안 된 머신은 cron 자체가 안 돔 | 가장 강력 |
| Skill 가드 | 명령 실행 시 — `CLAUDE_MACHINE_ID` 매칭 실패 시 exit 0 | `/schedule`, 수동 호출, cron 모두 |

둘 다 켜두면: 시스템 cron 에 등록한 머신만 cron 으로 실행 → skill 가드가 한 번 더 검증.

#### `/schedule` 도 쓰고 싶다면?

```
/schedule create config-push "5 * * * *" run /config-push
```
가능. 다만 다른 머신에서도 동시 트리거될 수 있어 **skill 머신 가드** 가 필수.
또는 머신별로 다른 이름으로 등록:
```
# Mac 에서만
/schedule create config-push-mac "5 * * * *" run /config-push
```
이러면 routine 이름 자체가 머신 종속.

---

### 양방향 자동 동기화 (권장 패턴)

```
[작업 머신]                            [작업 안 하는 머신]
─────────────                          ──────────────────
edit skills/foo                        (자고 있음)
                                       
   ↓ 매시간 :05                        
/config-push (자동)                    
  - secret scan                        
  - auto commit                        
  - rebase + push  ─────► origin/main  
                                       │
                                       │ 매일 07:30
                                       ▼
                                  /config-sync (자동)
                                  - git pull --rebase
                                  - hook 가 변경 요약
                                  - 재시작 안내
```

**등록 명령 (각 머신 1회씩):**
```
/schedule create config-push "5 * * * *"  run /config-push      # 매시간
/schedule create config-pull "30 7 * * *" run /config-sync      # 매일 07:30
```

### 동기화 방법 4가지

**1. 수동 `/config-sync` (가장 안전, 권장)**

```
/config-sync          # git pull + 변경 요약 + 재시작 안내
/config-sync --check  # pull 안 하고 변경 사항만 미리보기
```

자동 안전장치:
- 미커밋 변경 있으면 abort (lost work 방지)
- rebase 충돌 발생 시 자동 해결 X — 사용자에게 안내
- `plugins.manifest` 변경되면 `/sync-plugins` 권장 메시지

**2. post-merge hook (자동 알림)**

`git pull` 호출 시 hook 가 자동으로 변경 사항 콘솔에 출력:

```
[post-merge] config 변경 사항:
  + skills/new-feature/SKILL.md
  ~ skills/daily-log/SKILL.md
  - commands/old-command.md

[post-merge] 새 스킬/agent/command/hook 적용하려면 Claude Code 재시작 필요
```

수동 `git pull` 이든 `/config-sync` 든 결과로 trigger 됨.

**3. 매일 자동 pull routine**

각 머신에서 한 번만 등록:

```
/schedule create config-pull "30 7 * * *" run /config-sync
```

매일 출근 시간 전 (07:30) 자동 pull. 충돌 발생 시 cron 로그에 남고 다음번에 사용자 개입.

**4. 매시간 자동 push routine (`/config-push`)**

작업 머신에서 push 잊지 않게 자동:

```
/schedule create config-push "5 * * * *" run /config-push
```

매시간 5분에 변경 있으면 자동 commit + push. **secret pattern 자동 차단** (secret_*, Bearer, sk-ant, ghp_, glpat-, PRIVATE KEY 등). 발견 시 push abort + 알림.

⚠️ **자동 push 위험 인지**:
- 미완성 작업도 push 됨 (의식적 분기/PR 패턴이 필요한 큰 변경은 사용자가 먼저 수동 commit)
- auto 라벨 commit 메시지 — 의식적 메시지가 더 좋다면 수동 commit 우선
- secret false-negative 가능 — 진짜 secret 은 항상 paths.local.env (gitignored) 에
- 끄기: `/schedule delete config-push`

### 무엇이 바뀌면 재시작 필요?

| 변경 | 재시작 필요? |
|---|---|
| `skills/*` 추가/수정 | ✅ 필요 |
| `agents/*` 추가/수정 | ✅ 필요 |
| `commands/*` 추가/수정 | ✅ 필요 |
| `hooks/*` 추가/수정 | ❌ 다음 git 호출 시 자동 적용 |
| `plugins.manifest` 추가 | ✅ `/sync-plugins` 호출 + 재시작 |
| `paths.env` / `paths.local.env` 수정 | ❌ 셸 재시작 (또는 `source ~/.bashrc`) |
| `CLAUDE.md` 수정 | ✅ 재시작 (또는 `/memory` 재로드) |
| `bootstrap.sh` / `.ps1` 수정 | ❌ 다음 bootstrap 호출 시 적용 |

### 충돌 처리

두 머신에서 동시에 수정 후 둘 다 push 시도하면:
1. 먼저 push 한 쪽이 성공
2. 두 번째 머신은 `git push` 실패 (non-fast-forward)
3. 두 번째 머신에서 `/config-sync` (또는 수동 `git pull --rebase`)
4. rebase 충돌이면 사용자가 직접 해결:
   ```bash
   cd $CLAUDE_CONFIG_DIR
   # 충돌 파일 수정
   git add <파일들>
   git rebase --continue
   git push
   ```

### 일일 운영 흐름 예

```
[Mac mini]  09:00  edit skills/foo + git commit + push
[Ubuntu]   다음 날 07:30  /config-sync 자동 실행
                          → +1 skill (foo) 알림
                          → Claude Code 재시작 (다음 사용 시)
[WSL]      다음 날 07:30  /config-sync 자동 실행 (동일)
```

---

## 새 PC 셋업 — 한 곳 관리 모델

새 머신에서 손대야 할 모든 항목을 `paths.env` (공통) + `paths.local.env`
(머신별/secret) **두 파일**로 관리한다. bootstrap 이 자동 처리 + 외부 시스템
(GitHub/GitLab/Notion 웹) 만 사람이 직접.

### 처음 셋업 흐름 (요약)

```bash
# 1. clone
git clone https://github.com/kojunhyun/claude-config-setting.git ~/claude-config
cd ~/claude-config

# 2. bootstrap (자동)
./bootstrap.sh
# → 심볼릭링크 + env vars + paths.local.env 자동 생성
# → SSH key 자동 생성 (passphrase 없이, 이미 있으면 skip)
# → 회사 폴더 mkdir (OS별 자동: WSL=/mnt/d/Aixera, Mac=~/Aixera)
# → plugins.manifest 의 ECC 등 자동 설치

# 3. paths.local.env 채우기 (사람 직접)
vi ~/claude-config/paths.local.env
#   - CLAUDE_MACHINE_ID 의미있게
#   - CLAUDE_WEEKLY_LEADER=true   (Mac mini 한 대만)
#   - CLAUDE_LOG_NOTION_PERSONAL_TOKEN / _WORK_TOKEN

# 4. 셋업 상태 확인 (자동)
source ~/.bashrc
claude
> /setup-status
# → ✅ / ⏳ 체크리스트 + 남은 작업 + 정확한 명령/URL

# 5. ⏳ 표시 항목들 처리 (사람 직접)
#   - GitHub.com 공개키 등록
#   - gitlab.aixera.net 공개키 등록
#   - (필요 시) Notion integration token 발급
```

### Git/SSH single source of truth — paths.env

```env
# paths.env (git tracked, 모든 머신 공통)
GIT_PERSONAL_NAME="고준현"
GIT_PERSONAL_EMAIL="skykjh200@naver.com"
GIT_PERSONAL_KEY_NAME="id_ed25519"
GIT_PERSONAL_HOSTS="github.com"

GIT_WORK_NAME="고준현"
GIT_WORK_EMAIL="jhko@aixera.co.kr"
GIT_WORK_KEY_NAME="id_ed25519_aixera"
GIT_WORK_HOSTS="gitlab.aixera.net"

GIT_WORK_DIR=    # 비우면 OS별 자동: WSL=/mnt/d/Aixera, Mac/Linux=~/Aixera
GIT_CREDENTIAL_HELPER="store"
```

이 값들이 `/setup-status` 의 기대값 기준이 됨. 추후 새 호스트 추가 시
콤마 구분으로 한 줄 수정 후 git push → 다른 머신에서 git pull → `/setup-status`.

### 자동화 범위

| 항목 | 자동 처리 | 사람 직접 |
|---|---|---|
| 심볼릭링크 ~/.claude/* | ✅ bootstrap | |
| env vars 셸 rc 등록 | ✅ bootstrap | |
| paths.local.env 초기화 | ✅ bootstrap | 토큰/머신ID 채우기 |
| SSH key 생성 | ✅ bootstrap (없으면) | |
| 회사 폴더 mkdir | ✅ bootstrap | |
| 플러그인 설치 (ECC 등) | ✅ bootstrap | |
| `~/.gitconfig` 의 user/includeIf | ❌ | ✅ 사용자가 한 번 작성 (또는 기존 유지) |
| `~/.ssh/config` 의 host alias | ❌ | ✅ 사용자가 한 번 작성 |
| **GitHub/GitLab 에 공개키 등록** | ❌ | ✅ 머신마다 브라우저 |
| **Notion integration token 발급** | ❌ | ✅ 워크스페이스마다 1회 |
| 부모 페이지 자동 생성 | ✅ 첫 daily-log 호출 시 | |

> `~/.gitconfig` / `~/.ssh/config` 자동 작성을 안 하는 이유: 사용자가 기존에
> 직접 셋팅한 항목 (다른 계정, 다른 host alias) 을 망가뜨릴 위험. 대신
> `/setup-status` 가 무엇이 부족한지 정확히 알려주고, 그대로 복사할 수 있는
> 명령/블록을 출력한다.

### 일상 점검

```
/setup-status     # 셋업 누락 항목 즉시 표시 (셀프 진단)
/sync-plugins     # 플러그인 manifest 변경 후 재동기화
```

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
git pull                 # post-merge hook 자동 실행 (CLAUDE.md 동기화)
# 신규 명령/스킬은 Claude Code 재시작만 하면 인식
```

`post-merge` 훅이 `hooks/` 에서 자동 실행됨. Windows 만 CLAUDE.md copy 갱신, 나머지는 symlink 라 무작업.

---

## 다른 경로/드라이브로 이동

bootstrap 스크립트는 **자기 위치 기준**으로 동작. clone 어디 하든 OK.

**시나리오 A — 새 위치에 clone (기존 폐기)**

```bash
# 기존 위치 무관, 그냥 새 위치에 clone
git clone git@github.com:고준현/claude-config.git /mnt/e/MyClaude
cd /mnt/e/MyClaude
./bootstrap.sh
# → 모든 symlink/junction 새 위치로 재지정, env vars 값 자동 갱신, 옛 위치는 끊김
```

**시나리오 B — 기존 폴더 옮기기 (히스토리 보존)**

```bash
# 1. 폴더 이동
mv /mnt/d/00_Claude_Config /mnt/e/MyClaude

# 2. bootstrap 재실행 (스크립트가 새 위치 자동 감지)
cd /mnt/e/MyClaude
./bootstrap.sh
# → symlink/junction/env vars 자동 갱신
```

**시나리오 C — Custom 경로 지정**

```bash
# WSL/Mac/Linux
PROJECTS_DIR=/custom/path OBSIDIAN_DIR=/custom/notes ./bootstrap.sh
```

```powershell
# Windows
.\bootstrap.ps1 -ProjectsDir 'E:\MyProjects' -ObsidianDir 'E:\Notes'
```

bootstrap 은 idempotent — env vars block 마커로 감지해 **값만 갱신** (중복 안 쌓임).

---

## Git 훅 (자동 동기화)

`bootstrap` 이 `git config core.hooksPath hooks` 설정. 이후 모든 `git pull` 마다 `hooks/post-merge` 자동 실행:
- Linux/Mac/WSL: symlink 라 무작업
- Windows: CLAUDE.md copy 자동 갱신 (Dev Mode 없을 때 대응)

훅 추가/수정 시 `hooks/` 폴더 안에 두면 모든 clone 에서 즉시 적용.

---

## 플러그인 자동 셋업 (Hermes / OpenClaw 계열)

`plugins.manifest` 한 파일로 모든 머신의 플러그인을 동일하게 유지한다.

### 어떻게 동작?

1. 레포 루트의 `plugins.manifest` 는 git 으로 추적 (선언적 목록)
2. `bootstrap.{sh,ps1}` 가 실행 시 manifest 를 파싱해
   - `claude plugin marketplace add <source>`
   - `claude plugin install <plugin>@<market>`
   를 자동 실행
3. 실제 플러그인 파일은 `plugins/` 에 떨어지는데 `.gitignore` 됨 (per-machine)
4. 따라서 **새 머신: git clone → bootstrap → 동일 플러그인 즉시 설치 완료**

### 기본 활성화 플러그인

| 플러그인 | 출처 | 효과 |
|---|---|---|
| `ecc@ecc` | `affaan-m/everything-claude-code` | 60 agents + 232 skills + 75 commands. Hermes operator story 포함, harness 성능 최적화 종합판. |

### Manifest 편집

```bash
# 기본 비활성. 활성화하려면 줄 맨 앞 '#' 제거:
# market AlexAI-MCP/hermes-CCC      # Hermes-CCC (46 native skills)
# plugin hermes@hermes-ccc

# market moazbuilds/claudeclaw      # ClaudeClaw (OpenClaw-style 데몬)
# plugin claudeclaw@claudeclaw
```

편집 후:
- **머신 전체 적용**: `cd $CLAUDE_CONFIG_DIR && ./bootstrap.sh`
- **현재 세션만 동기화**: Claude Code 안에서 `/sync-plugins`

### 제거

manifest 에서 주석 처리는 *재설치 차단* 효과만 있고 자동 uninstall 은 안 한다.
명시적 제거:

```bash
claude plugin uninstall ecc
claude plugin marketplace remove ecc
```

### 트러블슈팅

| 증상 | 해결 |
|---|---|
| bootstrap 후 플러그인 안 보임 | Claude Code 재시작 (플러그인은 부팅 시 로드됨) |
| `claude` 명령 없다고 함 | `npm i -g @anthropic-ai/claude-code` 먼저, 그 후 bootstrap 재실행 |
| 토큰 비용이 너무 큼 | `claude plugin details <name>` 으로 컴포넌트 확인 후 manifest 에서 비활성화 |
| ECC 가 기존 leads 와 충돌하나? | namespace 분리되어 안 충돌. Arch 의 8 leads 는 그대로, ECC agents 는 추가로 사용 가능 |

---

## 멀티 머신 운영 (충돌 방지)

여러 머신(Win+WSL / macOS / Ubuntu 등)에 같은 셋업이 깔려 있고 같은 사용자
계정으로 Claude Code 를 쓸 때, daily/weekly 가 동시에 돌면 다음 문제가 생긴다:

1. **lost update**: 같은 Obsidian 파일/Notion 페이지를 동시 update → 마지막만 남음
2. **데이터 분절**: 각 머신은 자기 cwd 의 세션/git 만 봄 — 통합 불가
3. **N번 실행**: 같은 시간에 N대가 같은 작업 → 자원/비용 낭비

이를 막기 위해 두 가지 운영 변수가 있다:

| 변수 | 위치 | 의미 |
|---|---|---|
| `CLAUDE_MACHINE_ID` | `paths.local.env` (머신별) | 이 머신의 고유 식별자. 모든 daily 파일/Notion 페이지 이름에 박힘 |
| `CLAUDE_WEEKLY_LEADER` | `paths.local.env` (머신별) | `true` 면 weekly 통합 수행. 메인 머신 **1대만** true |

### 자동 초기화

`./bootstrap.sh` (또는 `.\bootstrap.ps1`) 첫 실행 시 **paths.local.env 가 없으면**
자동 생성하면서 `CLAUDE_MACHINE_ID=<user>-<hostname>` 을 디폴트로 박는다.
이미 있으면 건드리지 않는다.

```bash
# bootstrap 가 생성한 예시
cat paths.local.env
# CLAUDE_MACHINE_ID=jhko-wsl-desktop
# CLAUDE_WEEKLY_LEADER=
```

### 머신별 운영 패턴

각 머신에서:

```env
# WSL+Win (메인 머신, leader)
CLAUDE_MACHINE_ID=jhko-wsl-desktop
CLAUDE_WEEKLY_LEADER=true

# macOS
CLAUDE_MACHINE_ID=jhko-mac-mini
CLAUDE_WEEKLY_LEADER=

# Ubuntu
CLAUDE_MACHINE_ID=jhko-ubuntu-prod
CLAUDE_WEEKLY_LEADER=
```

### 동작 결과 (2-phase 워크플로)

| 시점 | 머신 | 명령 | 동작 |
|---|---|---|---|
| 매일 22:00 | **모든 머신** | `/daily-log` | 자기 머신의 raw 일지만 작성. Obsidian: `Daily/raw/2026-05-20_<MID>.md`, Notion: `[raw] 2026-05-20 (<MID>)`. 머신별 분리라 충돌 zero. |
| 매일 23:00 | **leader 만** | `/daily-log-aggregate` | 그 날 모든 머신 raw 를 통합한 **최종 일일 보고** 작성. Obsidian: `Daily/2026-05-20.md`, Notion: `Daily — 2026-05-20`. raw 는 그대로 보존. |
| 매주 목 12:30 | **leader 만** | `/weekly-log` | 지난 7일 final 파일을 합쳐 주간 통합 보고. Obsidian: `Weekly/2026-W21.md`, Notion: `Weekly — 2026-W21`. |
| 비리더에서 weekly/aggregate 호출 시 | non-leader | (어느 거든) | 안내 후 즉시 종료. 충돌 zero. |

### 폴더/페이지 최종 구조

**Obsidian** (모든 머신 공유):
```
Claude_Logs/
├── Daily/
│   ├── raw/                              ← 모든 머신이 매일 자기 파일만 추가
│   │   ├── 2026-05-20_jhko-wsl-desktop.md
│   │   ├── 2026-05-20_jhko-mac-mini.md
│   │   └── 2026-05-20_jhko-ubuntu-prod.md
│   ├── 2026-05-20.md                     ← leader 가 23:00 만든 통합 final
│   └── 2026-05-21.md
└── Weekly/
    └── 2026-W21.md                       ← leader 가 목 12:30 만든 통합
```

**Notion** (각 워크스페이스 동일 구조):
```
Claude Logs/
├── [raw] 2026-05-20 (jhko-wsl-desktop)   ← raw 페이지 (보관)
├── [raw] 2026-05-20 (jhko-mac-mini)
├── [raw] 2026-05-20 (jhko-ubuntu-prod)
├── Daily — 2026-05-20                    ← final
├── Daily — 2026-05-21
└── Weekly — 2026-W21
```

### Obsidian vault 동기화 전제

위 모델은 **모든 머신이 같은 Obsidian vault 를 공유**한다는 전제 위에서 동작:
- WSL+Win: D 드라이브 공유 (자동)
- macOS / Ubuntu: iCloud / Dropbox / git / SyncThing 등으로 vault 폴더 동기화

vault 가 분리되어 있으면 leader 가 다른 머신 daily 파일을 못 봐서 weekly 통합은
**Notion 에서만 가능**. Notion 은 워크스페이스 단위 통합이라 자동.

### `/schedule` 등록 정책

```
# 1. 모든 머신에서 등록 (각 머신이 자기 raw 만 작성)
/schedule create daily-raw "0 22 * * *" run /daily-log

# 2. leader 머신(예: Mac mini)에서만 추가 등록
/schedule create daily-aggregate "0 23 * * *"  run /daily-log-aggregate
/schedule create weekly-summary  "30 12 * * 4" run /weekly-log
```

타이밍 근거:
- 22:00 모든 머신 raw 작성 → 1시간 버퍼 → 23:00 leader 가 통합
- 만약 머신 중 일부가 22:00 ~ 23:00 사이 꺼져 있어 raw 가 없다면
  leader 는 있는 raw 만 통합 (누락 머신은 보고에 명시)
- 주간은 모든 일일 final 파일이 쌓인 후라 leader 만 호출하면 충분

> claude.ai 의 routine 이 사용자별 1회 실행인지 머신별 실행인지 정책이
> 변할 수 있다. 한 번 등록 후 며칠 관찰하면서 N번 실행되면 leader 외
> 머신에서는 `/schedule delete daily-raw` 로 해제.

### 시스템 cron 옵션 (Linux/WSL/Mac)

```cron
# 모든 머신
0  22 * * *  claude -p "/daily-log"             >> ~/.claude/logs/daily.log     2>&1

# leader 머신(Mac)만 추가
0  23 * * *  claude -p "/daily-log-aggregate"   >> ~/.claude/logs/aggregate.log 2>&1
30 12 * * 4  claude -p "/weekly-log"            >> ~/.claude/logs/weekly.log    2>&1
```

---

## 일일 / 주간 작업 로그 자동화

매일 작업한 내용 + 매주 목요일 12:30 주간 보고를 자동으로 Notion + Obsidian
양쪽에 저장.

### 구성 요소 (이미 repo 에 포함)

- `skills/daily-log/SKILL.md` — 오늘 세션 + git log 수집 → 마크다운 → 저장
- `skills/weekly-log/SKILL.md` — 지난 7일 집계 → 주간 보고
- `commands/daily-log.md` `/daily-log` 슬래시 명령
- `commands/weekly-log.md` `/weekly-log` 슬래시 명령

### 출력 위치

기본값:
- **Obsidian**: `$OBSIDIAN_DIR/Claude_Logs/Daily/YYYY-MM-DD.md`,
  `$OBSIDIAN_DIR/Claude_Logs/Weekly/YYYY-Www.md`
- **Notion**: `"Claude Logs"` 부모 페이지 하위에 일/주간 페이지
  (없으면 자동 생성, 부모 ID 는 `cache/notion-*-parent.txt` 에 캐시)

### 경로/페이지 커스터마이즈 (선택)

설정은 **`paths.env` / `paths.local.env`** 두 파일로 관리. bootstrap 이 셸 rc 에
auto-source 라인을 박아두므로 셸 시작 시 자동 로드 (bash/zsh + PowerShell 양쪽).

| 파일 | 추적 | 용도 |
|---|---|---|
| `$CLAUDE_CONFIG_DIR/paths.env` | git ✅ | 모든 머신 공통값 (Notion 페이지 이름/ID 등 머신 무관) |
| `$CLAUDE_CONFIG_DIR/paths.local.env` | git ❌ | 머신별 오버라이드 (절대경로 등 머신마다 다른 값) |

로드 순서: `paths.env` → `paths.local.env` (local 이 같은 키를 덮어씀).

| 환경변수 | 위치 | 효과 |
|---|---|---|
| `CLAUDE_LOG_OBS_DAILY` | paths.env / .local | 일일 파일 저장 경로 (기본 `$OBSIDIAN_DIR/Claude_Logs/Daily`) |
| `CLAUDE_LOG_OBS_DAILY_RAW` | paths.env / .local | raw 폴더 (기본 `$CLAUDE_LOG_OBS_DAILY/raw`) |
| `CLAUDE_LOG_OBS_WEEKLY` | paths.env / .local | 주간 파일 저장 경로 (기본 `$OBSIDIAN_DIR/Claude_Logs/Weekly`) |
| `CLAUDE_LOG_NOTION_TARGETS` | paths.env | Notion 타겟 콤마 구분 (예: `personal,work`) |
| `CLAUDE_LOG_NOTION_<T>_PARENT` | paths.env | 타겟 `<T>` 부모 페이지 이름 (기본 `Claude Logs`) |
| `CLAUDE_LOG_NOTION_<T>_PARENT_ID` | paths.env | 타겟 `<T>` 부모 페이지 ID 강제 (32자 hex) |
| `CLAUDE_LOG_NOTION_<T>_TOKEN` | **paths.local.env (secret)** | 타겟 `<T>` Notion integration secret (`secret_xxx...`) |
| `CLAUDE_LOG_ARCHIVE_RAW` | paths.env | `keep` (기본) / `archive` / `delete` — aggregate 후 raw 처리 |

#### 문법 규칙 (중요)

- 한 줄당 `KEY=value`. `#` 시작 줄은 주석.
- **값에 공백/한글/특수문자가 있으면 반드시 따옴표**:
  - ✅ `CLAUDE_LOG_NOTION_PARENT="개발 일지"`
  - ❌ `CLAUDE_LOG_NOTION_PARENT=개발 일지` (bash 가 "일지" 를 명령으로 해석)
- **`$VAR` expansion 사용 금지** — PowerShell 호환을 위해 literal 값만.
- **빈 값 = 기본 fallback 사용** (SKILL.md 의 `${VAR:-...}` 가 처리).

#### 예시 1 — Notion 부모 페이지 이름만 바꾸기 (공통값 → paths.env)

`paths.env` 편집 후 git 으로 모든 머신에 자동 전파:

```env
CLAUDE_LOG_NOTION_PARENT="개발 일지"
```

#### 예시 2 — Obsidian 폴더를 바꾸기 (머신별 → paths.local.env)

`paths.local.env` 생성 (gitignored):

```env
# WSL
CLAUDE_LOG_OBS_DAILY=/mnt/d/obsidian/02_Logs/Claude/Daily
CLAUDE_LOG_OBS_WEEKLY=/mnt/d/obsidian/02_Logs/Claude/Weekly
```

```env
# Mac
CLAUDE_LOG_OBS_DAILY=/Users/jhko/Obsidian/02_Logs/Claude/Daily
CLAUDE_LOG_OBS_WEEKLY=/Users/jhko/Obsidian/02_Logs/Claude/Weekly
```

> `$OBSIDIAN_DIR` 같은 expansion 을 쓰고 싶으면 paths.local.env 가 머신별이라
> OS/머신마다 절대경로로 명시. (paths.env 는 expansion 못 함 — PS1 호환 때문)

#### 예시 3 — Notion 부모를 특정 기존 페이지로 강제

```env
# paths.env (모든 머신 공통)
# Notion 페이지 URL 끝의 32자 hex 가 page ID
CLAUDE_LOG_NOTION_PARENT_ID=a1b2c3d4e5f6789012345678901234ab
```

#### 예시 4 — 개인 + 회사 노션 동시 업로드 (Token 방식)

**1단계: 각 워크스페이스에 integration 등록 + token 발급**

위 "Notion Integration Token 셋업" 절차를 **개인/회사 각각** 1회씩.

**2단계: `paths.env` 에 타겟 + 페이지 이름** (git 공유, secret 없음)

```env
CLAUDE_LOG_NOTION_TARGETS=personal,work

CLAUDE_LOG_NOTION_PERSONAL_PARENT="Claude Logs"
CLAUDE_LOG_NOTION_WORK_PARENT="Claude Logs"
```

**3단계: 각 머신의 `paths.local.env` 에 token 저장** (머신별, gitignored)

```env
CLAUDE_LOG_NOTION_PERSONAL_TOKEN="secret_xxx..."
CLAUDE_LOG_NOTION_WORK_TOKEN="secret_yyy..."
```

> token 은 워크스페이스 단위라 모든 머신에서 같은 값. 머신 셋업 시 한 번씩
> paste. 1Password 등에 보관 권장.

**4단계: 셸 재시작 → 첫 실행으로 부모 페이지 자동 생성**

```bash
source ~/.bashrc
/daily-log
```

→ 각 워크스페이스에 "Claude Logs" 부모 페이지가 자동 생성되고 ID 가
   `cache/notion-daily-{personal,work}-parent.txt` 로 캐시됨.

**부분 실패 동작**: 한 타겟 실패해도 나머지는 진행. 예:
```
✅ personal: raw page created (notion.so/abc...)
❌ work:     401 unauthorized — check token or page sharing
```

#### 적용

- 셸 재시작 (또는 `source ~/.bashrc`) → 환경변수 갱신
- 다음 `/daily-log` `/weekly-log` 부터 새 값 사용
- Notion 부모를 바꿨다면 **기존 캐시 삭제**:
  ```bash
  rm "$CLAUDE_CONFIG_DIR/cache/notion-"{daily,weekly}"-parent.txt" 2>/dev/null
  ```
- Obsidian 기존 파일 옮기고 싶으면 `mv` 한 번 같이

#### 기존 머신 업그레이드

이전에 bootstrap 돌렸던 머신은 셸 rc 의 env block 에 source 라인이 없을 수
있음. `./bootstrap.sh` (or `.\bootstrap.ps1`) 재실행하면 block 이 idempotent
교체되어 source 라인이 박힘.

### 수동 실행

```
/daily-log               # 오늘 작업 정리
/daily-log 2026-05-18    # 특정 날짜 백필
/weekly-log              # 직전 7일
/weekly-log 2026-W20     # 특정 주차
```

### 자동 실행 등록 (머신당 한 번)

**옵션 A — Claude Code `/schedule` 사용 (권장)**

```
/schedule create daily-summary  "0 22 * * *"  run /daily-log
/schedule create weekly-summary "30 12 * * 4" run /weekly-log
```

(주: routine 상태는 사용자 클라우드에 저장돼 머신 간 자동 동기화됨 —
한 머신에서 등록하면 다른 머신에선 또 등록할 필요 없음)

**옵션 B — 시스템 cron (Linux / WSL / macOS)**

```bash
crontab -e
# 추가:
0  22 * * *  cd $HOME && claude -p "/daily-log"  >> ~/.claude/logs/daily.log  2>&1
30 12 * * 4  cd $HOME && claude -p "/weekly-log" >> ~/.claude/logs/weekly.log 2>&1
```

**옵션 C — Windows Task Scheduler**

```powershell
# PowerShell
schtasks /Create /TN "ClaudeDaily"  /SC DAILY  /ST 22:00 /TR "claude -p /daily-log"
schtasks /Create /TN "ClaudeWeekly" /SC WEEKLY /D THU /ST 12:30 /TR "claude -p /weekly-log"
```

### 사전 준비

1. **Notion Integration Token 셋업** (워크스페이스마다 1회):
   아래 "Notion Integration Token 셋업" 섹션 따라하기. 발급된 token 을
   각 머신의 `paths.local.env` 에 저장 (gitignored).
2. **Obsidian vault 경로**: `$OBSIDIAN_DIR` 환경변수 (bootstrap 이 OS 별 자동 설정)
3. **첫 실행**: 수동으로 `/daily-log` 한 번 호출해 부모 페이지 자동 생성 + 인증 확인

---

## Notion Integration Token 셋업

claude.ai MCP OAuth 대신 **각 워크스페이스에 internal integration 등록** →
secret token 발급 → REST API 호출. 두 워크스페이스 동시 업로드가 자연스럽고
cron 등 비대화형 환경에서도 안정적.

### 워크스페이스마다 (개인 / 회사 각각)

1. https://www.notion.so/profile/integrations 접속 (또는 Notion 앱 → Settings
   → Connections → "Develop or manage integrations")
2. **+ New integration** 클릭
3. 설정:
   - **Name**: 예 `Claude Logs (Personal)` 또는 `Claude Logs (Work)`
   - **Associated workspace**: 해당 워크스페이스 선택
   - **Type**: Internal
   - **Capabilities**: Read content / Update content / Insert content 모두 ✓
4. **Save** → 다음 화면에서 **Internal Integration Secret** 복사
   (`secret_xxx...` 형태, **한 번만 표시**되므로 즉시 보관)
5. 사용할 부모 페이지에서 integration 권한 부여 (가장 자주 빠뜨림):
   - Notion 에서 부모 페이지(예: "Claude Logs") 열기
   - 우상단 `...` → **Connections** → **+ Add connections**
   - 방금 만든 integration 선택 → Confirm
   - **하위 페이지에도 자동 상속됨** (부모만 share 하면 됨)
6. 이 머신의 `paths.local.env` 편집:
   ```env
   CLAUDE_LOG_NOTION_PERSONAL_TOKEN="secret_xxx..."  # 개인 secret
   CLAUDE_LOG_NOTION_WORK_TOKEN="secret_yyy..."      # 회사 secret
   ```
7. 다른 머신에서도 같은 token 을 그 머신의 paths.local.env 에 paste
   (token 은 워크스페이스 단위이므로 머신 무관)

### 토큰 동작 검증

```bash
TOKEN="secret_xxx..."
curl -sS https://api.notion.com/v1/users/me \
  -H "Authorization: Bearer $TOKEN" \
  -H "Notion-Version: 2022-06-28"
# → 200 + bot user 정보 = OK
# → 401 = token 잘못
# → 200 이지만 빈 결과 = integration 이 어떤 페이지도 share 못 받음
```

### 보안

- `paths.local.env` 는 `.gitignore` 에 등재 — git 추적 안 됨
- 다만 평문 저장이므로:
  - 머신 disk 접근 권한 가진 사람은 볼 수 있음
  - 클립보드 / 스크린샷 / 백업에 섞이지 않도록 주의
  - 노출 의심 시 Notion 에서 integration **revoke** 후 재발급
- 더 강력한 격리가 필요하면 macOS Keychain / Windows Credential Manager
  / Linux libsecret 사용 (현재 미구현, 필요 시 별도 작업)

### Token 재발급 / 회수

- 노출됐거나 의심 시: integration 페이지에서 **Rotate secret** 또는 **Delete integration**
- 새 token 받으면 paths.local.env 의 값만 교체. SKILL/cache 변경 불필요.

### 트러블슈팅

| 증상 | 해결 |
|---|---|
| Notion 401 unauthorized | token 만료/잘못. `curl -H "Authorization: Bearer $TOKEN" https://api.notion.com/v1/users/me` 로 테스트. paths.local.env 재확인 |
| Notion 404 / page not found | integration 이 부모 페이지에 share 안 됨. Notion 부모 페이지 → ... → Connections → Add → 해당 integration |
| `Could not find page with ID` | cache 의 page ID 잘못. `rm cache/notion-*-parent.txt` 후 재실행 |
| 한 타겟만 실패 | 그 타겟 token 또는 share 권한 문제. 다른 타겟은 정상이면 부분 실패 격리 의도대로 동작 |
| Obsidian 만 저장됨 | 의도된 fallback. token 미설정/오류면 Notion 스킵 |
| 부모 페이지가 잘못된 워크스페이스에 생김 | token 이 다른 워크스페이스의 것 — paths.local.env 재확인 |
| cron 으로 안 돌아감 | `claude -p` 가 사용자 환경변수 못 받을 수 있음. cron 진입점에서 `source ~/.bashrc` 후 호출 |
| 오늘 작업 없는 날 | daily-log 는 빈 통계로 짧게 저장 (스킵 아님, 회고용 기록 유지) |

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
