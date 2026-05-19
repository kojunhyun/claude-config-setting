---
title: "{{MEETING_TITLE}}"
date: {{DATE}}
type: meeting
attendees:
{{ATTENDEES_YAML}}
tags:
  - meeting
  - {{PROJECT_TAG}}
notion_url: "{{NOTION_URL}}"
---

# {{MEETING_TITLE}}

**일시**: {{DATE}} {{TIME}}
**참석자**: {{ATTENDEES_INLINE}}
**작성**: OpenHarness `meeting-notes` skill

## 안건
{{AGENDA_LIST}}

## 논의 내용

{{DISCUSSION_SECTIONS}}

## 결정사항
{{DECISIONS}}

## 액션 아이템
{{ACTION_ITEMS_TABLE}}

### 작업 추적 (Obsidian Tasks 호환)
{{ACTION_ITEMS_CHECKBOXES}}

## 후속 과제 / 미해결
{{FOLLOWUPS}}

## 참고
- Notion 페이지: {{NOTION_URL}}
- 다음 미팅: {{NEXT_MEETING}}
- 관련 문서: {{RELATED_LINKS}}
