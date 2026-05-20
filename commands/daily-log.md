---
name: daily-log
description: 오늘(또는 지정한 날짜) Claude Code 작업을 자동 수집·요약해 Notion + Obsidian 에 저장.
---

# /daily-log [YYYY-MM-DD]

`daily-log` 스킬을 실행한다. 인자 없으면 오늘 날짜.

## 동작

1. `daily-log` 스킬 로드
2. `$CLAUDE_CONFIG_DIR/projects/*/` 안 오늘 수정된 세션 jsonl 스캔
3. 각 세션 cwd 에서 git log 수집
4. 마크다운으로 정리:
   - Obsidian: `$OBSIDIAN_DIR/Claude_Logs/Daily/YYYY-MM-DD.md`
   - Notion: "Claude Logs" 부모 페이지 하위에 일일 페이지

## 사용 예

```
/daily-log               # 오늘
/daily-log 2026-05-18    # 특정 날짜 (과거 백필)
```

## 자동 실행 등록 (한 번만)

매일 22:00 자동 호출하려면 Claude Code 내에서:

```
/schedule create daily "0 22 * * *" run /daily-log
```

또는 시스템 cron (Linux/WSL/Mac):

```cron
0 22 * * *  cd $HOME && claude -p "/daily-log" >> ~/.claude/logs/daily.log 2>&1
```
