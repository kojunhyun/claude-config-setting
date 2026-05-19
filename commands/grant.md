---
name: grant
description: 정부과제 공고를 받아 제안서 본문 + PPT용 HTML 시각자료 5종 생성.
---

# /grant {공고 파일 경로 또는 텍스트}

`grant-proposal` 스킬을 실행한다.

## 동작

1. `grant-proposal` 스킬 로드
2. 입력 (PDF/텍스트/URL) → 공고 분석
3. 기술 동향 조사 (필요시 `tech-research` 재사용)
4. 본문 작성 + 5종 HTML 시각자료 생성

## 사용 예

```
/grant ./2026_IITP_AI과제공고.pdf
```

```
/grant https://www.iitp.kr/kr/1/notice/...
```

```
/grant
공고 내용 직접 붙여넣기...
```

## 산출물

`$PROJECTS_DIR/grant-{slug}/`:
- `03-proposal.md` (본문)
- `pipeline/style1~5.html` (PPT 캡처용)
- `pipeline/INDEX.html` (5종 비교)

## 주의

- 거짓 실적/논문 생성 금지 — 사용자가 직접 입력해야 함
- 예산은 placeholder만 두고 사용자 확인 요청
- 본문 초안 후 사용자 수정 1회 반영
