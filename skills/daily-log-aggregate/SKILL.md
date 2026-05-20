---
name: daily-log-aggregate
description: |
  Leader 머신에서 호출. 그 날 모든 머신이 만든 raw daily-log 파일/페이지를
  읽어 하나의 통합 일일 보고서로 정리하고 Obsidian + Notion 에 저장.
  daily-log (raw) 의 후속 단계.
  Use this skill when the user runs `/daily-log-aggregate` or scheduled on leader.
when_to_use:
  - "/daily-log-aggregate 명령으로 시작"
  - "일일 통합 보고, daily aggregate 키워드"
  - "schedule 로 leader 머신에서 호출됨"
---

# Daily Log Aggregate — 머신별 raw 통합 → 최종 일일 보고

## 전제

- 이 머신이 **leader** (`CLAUDE_WEEKLY_LEADER=true` 또는 사용자 명시)
- 모든 머신이 같은 Obsidian vault 공유 (raw 폴더가 한 곳에 모임)
- 모든 머신이 같은 Notion 워크스페이스(들)에 raw 페이지를 만들었음

## 입력

- 기본: 오늘 날짜 (`date +%Y-%m-%d`)
- 옵션: `/daily-log-aggregate 2026-05-18` 처럼 특정 날짜 백필

## Stage 0: Leader 체크 + Guard

```bash
LEADER="${CLAUDE_WEEKLY_LEADER:-}"
case "$LEADER" in
  true|1|yes|y) ;;
  *)
    echo "[daily-log-aggregate] 이 머신은 leader 아님 — 종료"
    echo "  paths.local.env 에 CLAUDE_WEEKLY_LEADER=true 설정 필요"
    exit 0
    ;;
esac

DATE="${ARG_DATE:-$(date +%Y-%m-%d)}"
```

비리더에서 호출되면 즉시 안내 후 종료. 충돌 방지.

## Stage 1: Raw 수집

### A. Obsidian raw 폴더 스캔

```bash
OBS_DAILY="${CLAUDE_LOG_OBS_DAILY:-${OBSIDIAN_DIR:-$HOME/Obsidian}/Claude_Logs/Daily}"
OBS_RAW="${CLAUDE_LOG_OBS_DAILY_RAW:-$OBS_DAILY/raw}"

# 그 날짜의 모든 머신 raw 파일
RAWS=$(ls "$OBS_RAW/${DATE}_"*.md 2>/dev/null)
if [ -z "$RAWS" ]; then
  echo "[daily-log-aggregate] raw 파일 없음 — 오늘 daily-log 호출이 안 됐을 수 있음"
  echo "  최소한 leader 머신에서 /daily-log 먼저 호출 권장"
fi

# 각 raw 의 frontmatter 에서 MACHINE_ID 추출, 본문 보존
```

### B. Notion raw 페이지 검색 (각 타겟별, REST API)

각 타겟 `<T>` 마다:

```bash
TOKEN="${!CLAUDE_LOG_NOTION_${T_UPPER}_TOKEN}"
[ -z "$TOKEN" ] && { echo "[$T] token 없음 — Notion 부분 스킵"; continue; }

# 그 날짜 prefix 페이지 검색
curl -sS -X POST https://api.notion.com/v1/search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  --data "{\"query\":\"[raw] $DATE\",\"filter\":{\"property\":\"object\",\"value\":\"page\"}}" \
| jq -r '.results[] | select(.parent.page_id == "'"$PARENT_ID"'") | .id'
```

→ 그 타겟·그 날짜의 raw 페이지 ID 목록.

> Obsidian raw 와 Notion raw 의 내용은 사실상 동일이라 LLM 통합 시 Obsidian
> 한 쪽만 읽어도 충분. Notion 검색은 raw 페이지 ID 알아내기 위함
> (final 페이지에 raw 페이지 URL 링크 + archive 정책 적용).

## Stage 2: 통합 분석 (LLM)

수집된 N 머신 × 1 날짜 raw 내용을 보고 LLM 이 다음을 추출:

```markdown
---
date: 2026-05-20
type: daily-final
machines: [jhko-wsl-desktop, jhko-mac-mini, jhko-ubuntu-prod]
tags: [claude-code, daily, final]
---

# Claude Code 일일 통합 보고 — 2026-05-20

## 🎯 오늘의 전체 활동 한 줄

(N 머신 종합해서 가장 큰 한 가지)

## 📊 통합 통계

| 지표 | 합계 | WSL | Mac | Ubuntu |
|---|---|---|---|---|
| 세션 | 12 | 5 | 4 | 3 |
| 프로젝트 | 5 | 3 | 2 | 1 |
| 커밋 | 23 | 12 | 8 | 3 |

## 🚀 머신별 핵심 작업

### WSL+Win — jhko-wsl-desktop
- (raw 요약 핵심 1-3 줄)

### Mac — jhko-mac-mini
- ...

### Ubuntu — jhko-ubuntu-prod
- ...

## 🔄 크로스 머신 패턴

(같은 프로젝트를 두 머신에서 작업했나? 핸드오프 흔적? 충돌 가능성?)

- 예: "agent-tracking 레포: WSL에서 brunch B 작업 → Mac에서 동일 브랜치 hot-fix"

## 🧠 학습 / 결정 (모든 머신 합산)

(메모리 갱신 통합)

## ⚠️ 막힌 곳 / 위험

## 📝 내일 우선순위

## 🔗 Raw 참조

- [[2026-05-20_jhko-wsl-desktop]]
- [[2026-05-20_jhko-mac-mini]]
- [[2026-05-20_jhko-ubuntu-prod]]
- Notion raw: WSL / Mac / Ubuntu 페이지 링크
```

## Stage 3: 저장 (final)

### Obsidian (final 폴더)

```bash
FINAL_FILE="$OBS_DAILY/${DATE}.md"
# Write 도구로 Stage 2 마크다운 저장
# raw 파일들은 그대로 보존 ($OBS_RAW/)
```

폴더 구조:
```
Claude_Logs/Daily/
├── raw/
│   ├── 2026-05-20_jhko-wsl-desktop.md
│   ├── 2026-05-20_jhko-mac-mini.md
│   └── 2026-05-20_jhko-ubuntu-prod.md
└── 2026-05-20.md                          ← 이 스킬의 결과물
```

### Notion (final 페이지, 멀티 타겟, REST API)

`daily-log` 의 "Notion — 멀티 타겟 (Integration Token, REST API)" 패턴 그대로.
요약:

- 타겟마다 `_TOKEN` 으로 인증 (빈 token = 스킵)
- 부모 ID 결정: env var → cache → search → create
- 그 부모 하위에 final 페이지 생성:
  ```bash
  TITLE="Daily — ${DATE}"
  curl -sS -X POST https://api.notion.com/v1/pages \
    -H "Authorization: Bearer $TOKEN" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    --data "{
      \"parent\":{\"page_id\":\"$PARENT_ID\"},
      \"properties\":{\"title\":{\"title\":[{\"text\":{\"content\":\"$TITLE\"}}]}},
      \"children\": $BODY_JSON
    }"
  ```
- 같은 날짜 final 이미 있으면 옛 페이지 archive 후 새로 작성 (idempotent)
- raw 페이지는 건드리지 않음 (Stage 4 archive 정책에 따라 별도 처리)

## Stage 4: Raw archive (옵션)

`CLAUDE_LOG_ARCHIVE_RAW` 환경변수에 따라:
- `keep` (기본): raw 그대로 보관
- `archive`: Notion raw 페이지를 archived=true 로 (Obsidian 은 그대로)
- `delete`: Notion raw 페이지 archive 후 delete API 호출 (Obsidian 은 안 지움)

archive 호출:
```bash
curl -sS -X PATCH https://api.notion.com/v1/pages/$RAW_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  --data '{"archived": true}'
```

> raw 가 그대로 쌓이면 한 달에 30 × N 머신 페이지. 자주 운영하면 `archive`
> 권장. delete 는 비추 (실수 복구 어려움).

## Stage 5: 결과 보고

```
✅ Daily Aggregate (2026-05-20)
  raw inputs: 3 machines (wsl, mac, ubuntu)
  - Obsidian: $OBS_DAILY/2026-05-20.md
  - Notion personal: https://notion.so/...
  - Notion work:     https://notion.so/...
  raw archive: keep
```

## 에러 처리

- raw 파일 0개 → "오늘 daily-log 가 한 번도 호출 안 됨" 안내 후 종료
- 일부 머신만 raw 있음 → 있는 것만 통합, 누락 머신 보고에 명시
- Notion 인증 실패한 타겟 → 그 타겟만 skip, 다른 타겟/Obsidian 은 계속
- 같은 날짜 final 이미 있음 → 덮어쓰기 (idempotent)

## 무인 실행 호환성

`claude -p "/daily-log-aggregate"` 로 호출되면 비대화형:
- 사용자 입력 요청 금지
- leader 체크 실패 시 exit 0 (에러 아님, 무동작)
- MCP 인증 못 하면 Obsidian 만 저장하고 한 줄 경고

## 등록 예 (Mac 만)

```
/schedule create daily-aggregate "0 23 * * *" run /daily-log-aggregate
```

또는 system cron (Mac):
```cron
0 23 * * *  claude -p "/daily-log-aggregate" >> ~/.claude/logs/daily-aggregate.log 2>&1
```
