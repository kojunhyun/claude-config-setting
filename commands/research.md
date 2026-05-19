---
name: research
description: AI 기술 주제를 조사하고 비전공자도 이해할 HTML 노트로 Obsidian + Notion에 저장.
---

# /research {주제}

`tech-research` 스킬을 실행한다.

## 동작

1. `tech-research` 스킬 로드
2. 웹 검색 + 논문 검색
3. HTML 노트 + 마크다운 생성 → Obsidian + Notion 저장

## 사용 예

```
/research Mixture of Experts 최신 동향
```

```
/research RAG vs Fine-tuning 비교 (실무 관점)
```

```
/research 확산모델 (Diffusion) 기초 --심화
```

옵션 `--심화` 추가하면 수식/코드 포함 깊이 있는 분석.

## 산출물

- `/mnt/d/obsidian/Tech-Notes/{slug}/index.html` (시각화 포함)
- `/mnt/d/obsidian/Tech-Notes/{slug}/index.md` (Obsidian 노트용)
- Notion 페이지

## 주의

- 출처 명시 필수 (저자, 연도, 링크)
- 부정확한 정보 발견 시 그 자체로 보고
- 비유는 정확성을 해치지 않는 범위 내
