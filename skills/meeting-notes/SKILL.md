---
name: meeting-notes
description: |
  회의록을 구조화해 Notion + Obsidian 양쪽에 동시 저장. 음성 전사본/메모/거친 기록을 받아
  결정사항/액션아이템(담당자+기한)/논의/후속과제로 분리. Notion MCP로 직접 업로드 +
  $OBSIDIAN_DIR/Meetings/ 에 파일 저장.
  Use this skill when the user runs `/meeting` or shares meeting notes/transcripts.
when_to_use:
  - "/meeting 명령으로 시작"
  - "회의록, 미팅 노트, 회의 정리 키워드"
  - "사용자가 전사본/거친 메모를 붙여넣고 정리 요청"
---

# Meeting Notes — 회의록 정리 및 다중 저장

## 입력 형태

다음 중 하나:
- 음성 전사본 (Otter, Clova Note, 직접 받아쓰기)
- 거친 메모 (한 줄짜리 키워드 모음)
- 회의 녹화 텍스트 파일 경로
- 직접 붙여넣은 텍스트

부수 정보가 있으면 활용:
- 회의 제목, 일시, 참석자, 안건

## Stage 1: 구조화

입력에서 추출:

```yaml
title: "{회의명}"
date: "YYYY-MM-DD"
time: "HH:MM-HH:MM"  # 가능한 경우
attendees: ["이름1", "이름2", ...]
agenda:
  - "안건 1"
  - "안건 2"
```

본문 섹션:

```markdown
## 논의 내용
### {안건 1}
- 핵심 논의 (불릿)
- 다른 의견 (있다면)

### {안건 2}
- ...

## 결정 사항
- [DECIDED] {결정 내용} (제안자: {이름})

## 액션 아이템
| ID | 내용 | 담당자 | 기한 | 상태 |
|----|------|--------|------|------|
| A01 | {할 일} | {이름} | YYYY-MM-DD | TODO |

## 후속 과제 / 미해결
- {남은 질문}

## 참고
- {링크, 첨부, 다음 미팅 일정 등}
```

원본에 없는 정보는 추측하지 말 것. 담당자/기한이 명시 안 됐으면 `(미정)`으로 표시.

## Stage 2: Obsidian 저장

저장 경로: `$OBSIDIAN_DIR/Meetings/YYYY-MM-DD-{slug}.md`

파일 형식 (YAML frontmatter + 본문):

```markdown
---
title: "{회의명}"
date: 2026-MM-DD
type: meeting
attendees:
  - 이름1
  - 이름2
tags:
  - meeting
  - {프로젝트태그}
notion_url: "{Notion 페이지 URL — Stage 3 후 채움}"
---

# {회의명}

(Stage 1의 구조화 내용)

## 액션 아이템 추적
- [ ] {A01} {내용} — @{이름} (YYYY-MM-DD)
- [ ] {A02} ...
```

**팁**: Obsidian Dataview 플러그인이 있는 사용자라면 `- [ ]` 형식이 task로 자동 인식돼 통합 대시보드에서 확인 가능.

## Stage 3: Notion 업로드

Notion MCP (`mcp.notion.com/mcp`) 사용.

작업 순서:
1. `notion-search`로 "회의록" 또는 사용자가 지정한 부모 페이지 찾기
   - 사용자가 명시한 데이터베이스/페이지가 있으면 그쪽 우선
   - 처음이면 사용자에게 부모 페이지 한 번 확인
2. `notion-create-pages`로 새 페이지 생성
   - 제목: "{YYYY-MM-DD} {회의명}"
   - 내용: Stage 1의 마크다운을 Notion 블록으로 변환
3. 생성된 페이지 URL을 받아 Obsidian 파일의 `notion_url` frontmatter에 업데이트

만약 Notion MCP 인증 안 됐거나 실패하면:
- Obsidian 저장은 진행
- 사용자에게 "Notion 업로드 실패, 인증 필요" 메시지
- 산출물 디렉토리에 `notion-payload.md` 저장 (수동 복붙용)

## Stage 4: 사용자 보고

응답 형식 (간결하게):

```
회의록 정리 완료
- Obsidian: $OBSIDIAN_DIR/Meetings/2026-05-19-주간회의.md
- Notion: https://notion.so/...

핵심 결정 3건 / 액션아이템 5건
가장 빠른 마감: A03 (5월 22일, @홍길동)
```

## 주의

- **AI Meeting Notes 트랜스크립트**: Notion API는 이 블록 타입에 접근 못함. 사용자가 Notion AI Meeting Notes 페이지를 그대로 넣어달라고 하면, 페이지 본문은 가져올 수 있지만 트랜스크립트 자체는 못 옴을 안내.
- **개인정보**: 회의록에 주민번호/계좌번호 등 들어있으면 본문에 그대로 두지 말고 "[REDACTED]"로 마스킹 + 사용자에게 보고.
- **잘못된 정보 만들지 말 것**: 원본에 없는 인용/숫자/결정 절대 생성 금지.
