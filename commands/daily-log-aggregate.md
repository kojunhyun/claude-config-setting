---
name: daily-log-aggregate
description: Leader 머신에서 호출. 그 날 모든 머신 raw 일일 로그를 통합해 최종 일일 보고로 정리하고 Notion + Obsidian 에 저장.
---

# /daily-log-aggregate [YYYY-MM-DD]

`daily-log-aggregate` 스킬을 실행한다. 인자 없으면 오늘 날짜.

## 전제

- 이 머신이 leader 여야 함 (`paths.local.env` 의 `CLAUDE_WEEKLY_LEADER=true`)
- 비리더에서 호출하면 안내 후 즉시 종료 (충돌 방지)
- 모든 머신이 같은 Obsidian vault 공유 + 그 날 `/daily-log` 한 번 이상 돌아 있어야 의미 있음

## 동작

1. leader 인지 확인 (아니면 종료)
2. `$CLAUDE_LOG_OBS_DAILY_RAW` (`Claude_Logs/Daily/raw/`) 에서 그 날 모든 머신 raw 파일 수집
3. Notion 각 타겟에서 `[raw] {DATE}` prefix 페이지 검색
4. LLM 이 머신별 raw 를 한눈에 합쳐 **최종 일일 통합 보고** 작성
5. 저장:
   - Obsidian: `$OBSIDIAN_DIR/Claude_Logs/Daily/YYYY-MM-DD.md`
   - Notion (멀티 타겟): `Daily — YYYY-MM-DD` (각 워크스페이스)
6. raw 는 기본적으로 보존. `CLAUDE_LOG_ARCHIVE_RAW=archive` 면 Notion raw 페이지 archive.

## 사용 예

```
/daily-log-aggregate              # 오늘 통합
/daily-log-aggregate 2026-05-18   # 과거 백필
```

## 자동 실행 등록 (leader 머신만, 한 번)

각 머신이 `/daily-log` 를 22:00 에 끝낸다고 가정. leader 는 1시간 뒤(23:00)
통합:

```
/schedule create daily-aggregate "0 23 * * *" run /daily-log-aggregate
```

또는 시스템 cron:

```cron
0 23 * * *  claude -p "/daily-log-aggregate" >> ~/.claude/logs/daily-aggregate.log 2>&1
```
