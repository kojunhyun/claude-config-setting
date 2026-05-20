---
name: weekly-log
description: |
  지난 한 주(월~목 12:30 시점)간 Claude Code 작업을 집계해 주간 보고서를 만들고
  Notion + Obsidian 에 저장. daily-log 가 만든 일일 파일 7개와 git/세션 데이터를
  합쳐 프로젝트별/도메인별 진척도, 주요 결정, 다음주 과제를 정리한다.
  Use this skill when the user runs `/weekly-log` or scheduled Thursday 12:30.
when_to_use:
  - "/weekly-log 명령으로 시작"
  - "주간 작업 정리, 주간 보고, weekly log 키워드"
  - "schedule 로 매주 목요일 호출됨"
---

# Weekly Log — Claude Code 주간 작업 정리

## 목적

매주 **목요일 12:30** 자동 호출되어 지난 7일 작업을 집계.
실제 운영상 "주간" = `이번주 목요일 12:30 기준 직전 7일` (지난 목 12:30 ~ 이번 목 12:30).

## 입력

- 기본: 오늘 기준 직전 7일
- 옵션: `/weekly-log 2026-W20` 또는 `/weekly-log --since 2026-05-12 --until 2026-05-19`

## Stage 0: Leader 체크 (멀티 머신)

여러 머신에서 weekly 가 동시에 돌면 통합이 깨지므로 **명시적 leader 한 대만**
실제 통합을 수행. 비리더에서 호출되면 즉시 종료.

```bash
LEADER="${CLAUDE_WEEKLY_LEADER:-}"
MID="${CLAUDE_MACHINE_ID:-$(hostname | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')}"

case "$LEADER" in
  true|1|yes|y) ;;
  *)
    echo "[weekly-log] 이 머신은 leader 아님 — 종료"
    echo "  paths.local.env 에 CLAUDE_WEEKLY_LEADER=true 설정 필요"
    exit 0
    ;;
esac
```

## Stage 1: 데이터 수집

### A. daily-log-aggregate 가 만든 final 일일 파일 7개 읽기

```bash
OBS_DAILY="${CLAUDE_LOG_OBS_DAILY:-${OBSIDIAN_DIR:-$HOME/Obsidian}/Claude_Logs/Daily}"
# 지난 7일 final 파일 패턴: YYYY-MM-DD.md (머신 suffix 없음 — leader 가 통합한 결과)
for i in 0 1 2 3 4 5 6; do
  D=$(date -d "$END_DATE -$i day" +%Y-%m-%d)
  [ -f "$OBS_DAILY/$D.md" ] && cat "$OBS_DAILY/$D.md"
done
```

- final 파일은 leader 가 매일 23:00 `/daily-log-aggregate` 로 만든 것
- 없는 날(aggregate 가 안 돈 날)은 **raw 폴더에서 직접 읽어 통합** fallback:
  ```bash
  for f in "$OBS_DAILY/raw/${D}_"*.md; do
    [ -f "$f" ] && cat "$f"
  done
  ```
- 그래도 없으면 그날은 빈 day 로 처리

### B. 주간 누계 git 활동

```bash
SINCE_DATE="..."  # 지난 목 12:30
UNTIL_DATE="..."  # 이번 목 12:30

# $PROJECTS_DIR/* 모든 git repo 순회
find "${PROJECTS_DIR:-$HOME/Projects}" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read git_dir; do
  repo=$(dirname "$git_dir")
  commits=$(git -C "$repo" log --since="$SINCE_DATE" --until="$UNTIL_DATE" \
            --pretty=format:"- %h %s (%an, %ad)" --date=short 2>/dev/null)
  [ -n "$commits" ] && { echo "## $repo"; echo "$commits"; echo; }
done
```

### C. 마일스톤 후보 (있으면)

- 머지된 PR (`gh pr list --state merged --search "merged:>=$SINCE_DATE"`)
- 닫힌 이슈 (`gh issue list --state closed --search "closed:>=$SINCE_DATE"`)
- 새로 만든 프로젝트 디렉토리 (`find $PROJECTS_DIR -maxdepth 2 -type d -newermt $SINCE_DATE`)

## Stage 2: 분석 + 구조화

LLM 이 수집한 raw 데이터를 보고 다음을 추출:

```markdown
---
week: 2026-W20
range: 2026-05-15 to 2026-05-21
type: weekly-log
tags: [claude-code, weekly]
---

# 주간 작업 정리 — Week {YYYY-Www}
## ({SINCE} ~ {UNTIL})

## 🎯 이번주 한 줄 요약

{한 문장. 가장 큰 진척 1개.}

## 📊 통계

| 지표 | 값 |
|---|---|
| Claude Code 세션 | {N}회 |
| 작업한 프로젝트 | {N}개 |
| 커밋 | {N}개 |
| 머지된 PR | {N}개 |
| 메모리 갱신 | {N}건 |

## 🚀 프로젝트별 진척

### {project-1}
- **상태**: in-progress / shipped / paused
- **주요 작업**:
  - 월: ...
  - 화: ...
  - ...
- **다음 단계**: ...

### {project-2}
...

## 🏆 마일스톤

- {merged PR / closed issue / shipped feature}
- ...

## 🧠 학습 / 결정

(이번주 메모리에 추가된 feedback/project 메모 중 의미있는 것 요약)

- ...

## ⚠️ 막힌 곳 / 위험

(daily-log 의 "막힌 곳" 섹션 + 미완 작업)

- ...

## 📅 다음주 과제

- [ ] ...
- [ ] ...

## 🔗 참조

- Daily logs: [[2026-05-15]] [[2026-05-16]] ... [[2026-05-21]]
- Notion: {parent-link}
```

## Stage 3: 저장

경로/이름은 **환경변수로 오버라이드 가능**. 설정은 `paths.env` /
`paths.local.env`. daily-log 와 동일 패턴 (멀티 타겟 지원).

### Obsidian

```bash
OBS_WEEKLY="${CLAUDE_LOG_OBS_WEEKLY:-${OBSIDIAN_DIR:-$HOME/Obsidian}/Claude_Logs/Weekly}"
mkdir -p "$OBS_WEEKLY"

# leader 만 실행 도달하므로 단순:
FILE="$OBS_WEEKLY/${WEEK_NUM}.md"
```

ISO 주차 계산:
```bash
WEEK_NUM=$(date -d "$END_DATE" +%G-W%V)
```

### Notion — 멀티 타겟 (Integration Token, REST API)

`daily-log-aggregate` 의 "Notion (final 페이지)" 섹션과 **동일한 REST API 패턴**.
(이 스킬은 Stage 0 에서 비리더면 이미 종료했으므로 추가 가드 불필요.)

각 타겟마다:
- `$CLAUDE_LOG_NOTION_<T>_TOKEN` 으로 인증 (없으면 스킵)
- 부모 ID 결정 (env var → cache `notion-weekly-<T>-parent.txt` → search → create)
- final 주간 페이지 생성: `Weekly — {YYYY-Www}`
- 같은 주차 페이지 있으면 archive 후 새로 작성 (idempotent)

요약:

1. `$CLAUDE_LOG_NOTION_TARGETS` (콤마 구분, 기본 `default`) 를 읽어 타겟 목록 결정
2. 타겟 `<T>` 마다 변수 lookup:
   - `CLAUDE_LOG_NOTION_<T>_MCP` — MCP 서버 이름 (비면 자동 탐지)
   - `CLAUDE_LOG_NOTION_<T>_PARENT` — 부모 페이지 이름 (기본 "Claude Logs")
   - `CLAUDE_LOG_NOTION_<T>_PARENT_ID` — ID 강제 (있으면 search 스킵)
3. 각 타겟의 부모 ID 결정 (캐시 파일은 **주간용 별도**):
   - `$CLAUDE_CONFIG_DIR/cache/notion-weekly-<T>-parent.txt`
   - default 타겟은 `notion-weekly-parent.txt` 로 호환 유지
4. 각 타겟의 부모 하위에 페이지 생성:
   - 제목: `Weekly — {YYYY-Www}`
   - 본문: Stage 2 마크다운
   - 속성 (DB 형태일 때): Week, Project Count, Commit Count, PR Count, Status
5. 부분 실패는 타겟별로 격리, 보고는 마지막에 한 번에

부모 옮기기:
- 이름만 바꿈 → `rm $CLAUDE_CONFIG_DIR/cache/notion-weekly-<T>-parent.txt` 후 재실행
- 특정 페이지로 강제 → `CLAUDE_LOG_NOTION_<T>_PARENT_ID=<32hex>` 로 고정

## Stage 4: 결과 보고

```
✅ Weekly log saved (Week 2026-W20)
  - Obsidian: $OBSIDIAN_DIR/Claude_Logs/Weekly/2026-W20.md
  - Notion:   https://notion.so/{page-id}
  - Stats: 12 sessions / 5 projects / 23 commits / 3 PRs
```

## 에러 처리 / 무인 실행

`daily-log` 와 동일 원칙:
- daily-log 파일이 부족해도 raw 데이터로 fallback
- Notion 인증 실패 → Obsidian 만 + 경고
- 이미 같은 주차 파일 있으면 **덮어쓰기** (idempotent)
- 비대화형: 사용자 입력 금지, 결정은 합리적 기본값
