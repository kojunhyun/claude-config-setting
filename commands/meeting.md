---
name: meeting
description: 회의 전사본/메모를 구조화해 Notion + Obsidian에 동시 저장.
---

# /meeting {전사본 또는 파일 경로}

`meeting-notes` 스킬을 실행한다.

## 동작

1. `meeting-notes` 스킬 로드
2. 입력에서 결정사항/액션아이템/논의 추출
3. Obsidian (`/mnt/d/obsidian/Meetings/`) + Notion 동시 저장

## 사용 예

```
/meeting ./오늘회의-전사본.txt
```

```
/meeting
회의명: 주간 정기회의 (5/19)
참석자: 김팀장, 이대리, 박사원
... (메모 본문)
```

## 산출물

- `/mnt/d/obsidian/Meetings/2026-MM-DD-{slug}.md`
- Notion 페이지 (URL은 응답에 표시)

## 주의

- 원본에 없는 내용 추측 금지 — 미정인 항목은 "(미정)"
- 민감정보(개인정보) 자동 마스킹
- Notion 인증 실패 시 Obsidian만 저장 + 안내
