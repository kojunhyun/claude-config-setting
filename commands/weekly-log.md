---
name: weekly-log
description: 지난 한 주 Claude Code 작업을 집계해 주간 보고서로 정리하고 Notion + Obsidian 에 저장.
---

# /weekly-log [YYYY-Www | --since DATE --until DATE]

`weekly-log` 스킬을 실행한다. 인자 없으면 오늘 기준 직전 7일.

## 동작

1. `weekly-log` 스킬 로드
2. `$OBSIDIAN_DIR/Claude_Logs/Daily/` 의 지난 7일 파일 읽기
   (없는 날은 세션/git 직접 재수집)
3. 누계 통계 + 프로젝트별 진척 + 다음주 과제 합치기
4. 저장:
   - Obsidian: `$OBSIDIAN_DIR/Claude_Logs/Weekly/YYYY-Www.md`
   - Notion: "Claude Logs" 부모 페이지 하위 주간 페이지

## 사용 예

```
/weekly-log                              # 오늘 기준 직전 7일
/weekly-log 2026-W20                     # ISO 주차 지정
/weekly-log --since 2026-05-12 --until 2026-05-19
```

## 자동 실행 등록 (한 번만)

매주 **목요일 12:30** 자동 호출:

```
/schedule create weekly "30 12 * * 4" run /weekly-log
```

또는 시스템 cron:

```cron
30 12 * * 4  cd $HOME && claude -p "/weekly-log" >> ~/.claude/logs/weekly.log 2>&1
```
