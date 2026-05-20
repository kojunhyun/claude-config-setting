---
name: daily-log
description: |
  이 머신(MACHINE_ID)에서 오늘 Claude Code 로 한 작업을 raw 일지로 수집해
  Obsidian raw 폴더 + Notion 임시 페이지에 업로드. 머신별 분리 저장이라 충돌 X.
  최종 통합 일일 보고는 leader 머신이 /daily-log-aggregate 로 합쳐 만든다.
  Use this skill when the user runs `/daily-log` or when scheduled at end of day.
when_to_use:
  - "/daily-log 명령으로 시작"
  - "오늘 작업 정리, 일일 작업 일지, daily log 키워드"
  - "schedule 로 매일 호출됨"
---

# Daily Log (raw) — 머신별 일일 작업 수집

## 목적

매일 저녁 모든 머신에서 호출되어 **그 머신에서만 한 작업** 을 자동 수집·정리해
**raw 형태**로 Obsidian + Notion 에 업로드. 머신별 파일/페이지 분리라 충돌 zero.

여러 머신 raw 를 종합한 **최종 일일 보고**는 leader 머신이 `/daily-log-aggregate`
로 만든다 (별도 스킬).

대화형이 아니라 **무인 실행 가능**해야 함 (`claude -p` / schedule routine).

## 입력

- 기본: 오늘 날짜 (`date +%Y-%m-%d`)
- 옵션: 사용자가 특정 날짜 지정 (`/daily-log 2026-05-18`)

## Stage 0: 머신 가드 (multi-machine 안전)

```bash
ALLOWED="${SCHEDULE_DAILY_MACHINES:-}"
MID="${CLAUDE_MACHINE_ID:-$(hostname | tr '[:upper:]' '[:lower:]')}"
if [ -n "$ALLOWED" ]; then
  if ! echo ",$ALLOWED," | grep -q ",$MID,"; then
    echo "[daily-log] $MID 는 SCHEDULE_DAILY_MACHINES 목록에 없음 — skip"
    exit 0
  fi
fi
```

일반적으로 모든 머신이 자기 raw 작성해야 하므로 빈값 권장. 특정 머신만
일일 로그 만들고 싶으면 paths.env 에 명시.

## Stage 1: 데이터 수집 (병렬)

다음 소스를 **병렬 Bash** 로 수집한다:

### A. Claude Code 세션 메타데이터

```bash
TODAY="${TARGET_DATE:-$(date +%Y-%m-%d)}"
PROJECTS_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

# 오늘 수정된 세션 jsonl 파일들
find "$PROJECTS_BASE" -name "*.jsonl" -newermt "$TODAY" \
     ! -newermt "$TODAY +1 day" 2>/dev/null
```

각 파일에 대해:
- 디렉토리명을 escape 해제해서 작업 cwd 알아냄
  (예: `-mnt-d-00-Project-foo` → `/mnt/d/00_Project/foo`)
- 파일 크기, 라인 수, 최초/최종 수정 시간 추출
- (선택) jsonl 첫 user 메시지 첫 줄을 세션 주제로 사용

### B. 프로젝트 git activity

```bash
# 작업한 것으로 추정되는 디렉토리 목록 (위 A 에서 추출한 cwd 들)
# 각 디렉토리에서:
for dir in "${WORK_DIRS[@]}"; do
  [ -d "$dir/.git" ] || continue
  echo "## $dir"
  git -C "$dir" log --since="$TODAY 00:00" --until="$TODAY 23:59" \
      --pretty=format:"- %h %s (%an)" 2>/dev/null
  echo
  git -C "$dir" diff --shortstat \
      "@{$TODAY 00:00}" "@{$TODAY 23:59}" 2>/dev/null
done
```

### C. 명령/메모리 컨텍스트

```bash
# 오늘 메모리 변경
find "$CLAUDE_CONFIG_DIR/projects" -path "*/memory/*.md" -newermt "$TODAY" \
     ! -newermt "$TODAY +1 day" 2>/dev/null
```

수집 실패해도 skill 은 **계속 진행** — 빈 섹션으로 두고 다음 단계로.

## Stage 2: 구조화

다음 마크다운 템플릿으로 합친다:

```markdown
---
date: {YYYY-MM-DD}
type: daily-log
tags: [claude-code, daily]
---

# Claude Code 일일 작업 — {YYYY-MM-DD}

## 🎯 오늘의 주요 활동

{LLM 이 세션/커밋/메모리 변화를 보고 3-5줄 자연어 요약}

## 📂 작업한 프로젝트

| 프로젝트 | 세션 수 | 커밋 | 변경 |
|---|---|---|---|
| `/path/to/foo` | 3 | 2 | +120 -45 |
| ... | ... | ... | ... |

## 🧠 Claude Code 세션

### 1. /path/to/foo — 14:20-16:05 (1h 45m)
- 첫 메시지: "다음 PR 의 마이그레이션 검토..."
- 세션 사이즈: 230 lines

### 2. ...

## 💾 git 활동

### /path/to/foo
- `a1b2c3d` feat: add user auth flow (kojh)
- `e4f5g6h` fix: timezone bug in scheduler (kojh)
- shortstat: 3 files changed, 120 insertions(+), 45 deletions(-)

## 🧬 메모리 / 학습 갱신

- `feedback_testing.md` — 새로 추가
- `user_role.md` — 갱신

## 📝 메모

(있으면 사용자가 직접 입력한 컨텍스트, 없으면 생략)
```

## Stage 3: 저장

저장 경로/이름은 **환경변수로 오버라이드 가능**. 설정은 `paths.env` /
`paths.local.env` 에서 관리 (bootstrap 이 셸 rc 에 auto-source 라인 박음).

### 머신 식별 (충돌 방지 핵심)

여러 머신에서 같은 시간에 호출될 수 있으므로 **모든 산출물에 머신 ID 포함**.

```bash
MID="${CLAUDE_MACHINE_ID:-$(hostname | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')}"
# bootstrap 이 paths.local.env 에 자동 세팅. 비어있으면 hostname fallback.
```

### Obsidian (raw 폴더)

```bash
OBS_DAILY="${CLAUDE_LOG_OBS_DAILY:-${OBSIDIAN_DIR:-$HOME/Obsidian}/Claude_Logs/Daily}"
OBS_RAW="${CLAUDE_LOG_OBS_DAILY_RAW:-$OBS_DAILY/raw}"
mkdir -p "$OBS_RAW"
# 파일 경로: $OBS_RAW/YYYY-MM-DD_<MACHINE_ID>.md
# 예) Claude_Logs/Daily/raw/2026-05-20_jhko-wsl-desktop.md
#     Claude_Logs/Daily/raw/2026-05-20_jhko-mac-mini.md
#     Claude_Logs/Daily/raw/2026-05-20_jhko-ubuntu-prod.md
```

- 모든 머신이 같은 vault 공유한다는 전제 (D 드라이브/iCloud/git 등)
- 한 머신에서 같은 날짜 다시 호출 시 자기 파일 덮어씀 (idempotent)
- leader 의 aggregate 가 raw/ 폴더 통째 스캔해서 final 작성

> vault 가 공유되지 않으면 leader 가 다른 머신 raw 파일을 못 봄. 그 경우
> 통합은 Notion 에서만 가능 (워크스페이스 단위 자동 통합).

### Notion — 멀티 타겟 (Integration Token, REST API)

#### 타겟 목록 결정

```bash
TARGETS="${CLAUDE_LOG_NOTION_TARGETS:-default}"
```

각 타겟 `<T>` 에 대해 다음 변수 lookup (bash indirect `${!VAR}`):

| 변수 | 의미 | 위치 |
|---|---|---|
| `CLAUDE_LOG_NOTION_<T>_TOKEN` | **secret token** (`secret_xxx...`) | paths.local.env (gitignored) |
| `CLAUDE_LOG_NOTION_<T>_PARENT` | 부모 페이지 이름 (search 용) | paths.env |
| `CLAUDE_LOG_NOTION_<T>_PARENT_ID` | 부모 페이지 ID 강제 (없으면 search) | paths.env |

token 이 비어있으면 그 타겟은 **스킵하고 Obsidian 만 진행** (실패 아님).

#### 공통 헤더

```bash
TOKEN_VAR="CLAUDE_LOG_NOTION_${T_UPPER}_TOKEN"
TOKEN="${!TOKEN_VAR}"
[ -z "$TOKEN" ] && { echo "[$T] token 없음 — Notion 스킵"; continue; }

AUTH="Authorization: Bearer $TOKEN"
NVER="Notion-Version: 2022-06-28"
CT="Content-Type: application/json"
```

#### 부모 페이지 결정 우선순위

1. `_PARENT_ID` env var 있으면 그 ID
2. 캐시 `$CLAUDE_CONFIG_DIR/cache/notion-daily-<T>-parent.txt` 있으면 사용
3. 둘 다 없으면 **search**:
   ```bash
   curl -sS -X POST https://api.notion.com/v1/search \
     -H "$AUTH" -H "$NVER" -H "$CT" \
     --data "{\"query\":\"$PARENT_NAME\",\"filter\":{\"property\":\"object\",\"value\":\"page\"}}" \
   | jq -r '.results[0].id // empty'
   ```
4. search 결과 없으면 워크스페이스 루트에 새 페이지 생성:
   ```bash
   curl -sS -X POST https://api.notion.com/v1/pages \
     -H "$AUTH" -H "$NVER" -H "$CT" \
     --data "{
       \"parent\":{\"workspace\":true},
       \"properties\":{\"title\":{\"title\":[{\"text\":{\"content\":\"$PARENT_NAME\"}}]}}
     }" \
   | jq -r '.id'
   ```
5. 결정된 ID 를 캐시 파일에 저장

> **Integration 권한**: 부모 페이지에 해당 integration 이 share 되어 있어야
> 위 호출이 200 을 받는다. share 안 됐으면 401/404 → 사용자에게 안내.

#### 페이지 생성 (raw, 머신별 분리)

```bash
TITLE="[raw] ${DATE} (${MID})"
# 본문 마크다운을 Notion blocks 로 변환 (간단 변환 또는 한 paragraph 로 통째)
BODY_JSON=$(jq -Rn --arg t "$BODY" '[{"object":"block","type":"paragraph","paragraph":{"rich_text":[{"text":{"content":$t}}]}}]')

curl -sS -X POST https://api.notion.com/v1/pages \
  -H "$AUTH" -H "$NVER" -H "$CT" \
  --data "{
    \"parent\":{\"page_id\":\"$PARENT_ID\"},
    \"properties\":{\"title\":{\"title\":[{\"text\":{\"content\":\"$TITLE\"}}]}},
    \"children\": $BODY_JSON
  }"
```

> 본문 마크다운이 너무 길면 Notion 의 100 block 제한이 걸릴 수 있다. 그 경우
> 마크다운을 청크 분할 + 추가 `PATCH /v1/blocks/{id}/children` 호출.
> 또는 본문을 한 `code` 블록(language=markdown)으로 통째 넣어도 됨.

#### 같은 날짜 재실행 (idempotent)

- 같은 머신·날짜로 두 번 실행 시 기존 raw 페이지를 update:
  ```bash
  # search 로 기존 페이지 ID 찾고 PATCH /v1/blocks/{page_id}/children 로
  # 기존 자식 블록 모두 제거 후 새로 쓰기. 또는 간단히 새 페이지 만들고
  # 옛 페이지는 archived=true 처리.
  ```
- 권장: **archive 후 새로 작성** (구현 단순). 옛 raw 도 검색 안 되니 충돌 없음.

#### 부분 실패 격리

```
✅ personal: raw page created (notion.so/abc...)
❌ work:     401 unauthorized — token invalid or page not shared
```

Obsidian 은 token 무관하게 항상 저장됨.

#### 부분 실패 정책

한 타겟이 실패해도 다른 타겟은 계속 진행. 보고:
```
✅ personal: saved (notion.so/abc...)
❌ work:     auth failed — skipped
```

#### 부모 옮기기

- 페이지 이름만 바뀜 → 해당 타겟 캐시 삭제 후 재실행
  (`rm $CLAUDE_CONFIG_DIR/cache/notion-daily-<T>-parent.txt`)
- 특정 페이지로 강제 → `CLAUDE_LOG_NOTION_<T>_PARENT_ID=<32hex>` 로 고정

## Stage 4: 결과 보고

대화형 호출일 때만 사용자에게 보고:
```
✅ Daily log saved
  - Obsidian: $OBSIDIAN_DIR/Claude_Logs/Daily/2026-05-19.md
  - Notion:   https://notion.so/{page-id}
```

무인(`claude -p`) 호출일 때는 종료 코드 0 + 한 줄 로그만.

## 에러 처리

- 세션 디렉토리 없음 → 빈 섹션으로 진행
- Notion MCP 인증 실패 → Obsidian 만 저장, 콘솔에 경고
- Obsidian 경로 없음 → `$OBSIDIAN_DIR` 못 찾으면 `$HOME/Obsidian` fallback,
  그것도 없으면 `$CLAUDE_CONFIG_DIR/cache/daily-logs/` 에 임시 저장
- 권한 오류 → 다음 실행에서 재시도하도록 그대로 throw

## 무인 실행 호환성 메모

`claude -p "/daily-log"` 로 호출하면 비대화형. 즉:
- 사용자 입력 요청 금지 (모든 결정은 합리적 기본값)
- MCP 자동 인증 가능 여부에 의존 — 인증 안 되어 있으면 Obsidian 만
- 스킬은 idempotent: 같은 날짜로 두 번 호출하면 **덮어쓰기**
  (Obsidian 은 파일 overwrite, Notion 은 기존 페이지 update)
