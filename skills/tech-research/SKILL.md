---
name: tech-research
description: |
  AI 기술 주제를 웹 검색 + 논문 검색으로 조사하고 비전공자도 이해할 수 있게 HTML 노트로 정리.
  Obsidian + Notion 양쪽에 저장. grant-proposal에서 재사용되기도 함.
  Use this skill when the user runs `/research` or asks to research an AI/ML topic
  and produce an accessible summary (e.g. "MoE 최신 동향 정리해줘",
  "RAG vs Fine-tuning 비교", "확산모델 기초 설명").
when_to_use:
  - "/research 명령으로 시작"
  - "기술 조사, 동향, 비교, 정리 키워드"
  - "AI/ML 특정 주제에 대한 깊이있는 정리 요청"
---

# Tech Research — AI 기술 조사 + HTML 정리

## 목적

- AI 기술 주제를 깊이있게 조사
- **비전공자도 이해 가능**한 수준으로 풀어 설명 (쉬운 비유 필수)
- 전문성 동시 확보 (정확한 용어, 출처 인용)
- HTML 노트로 시각적 정리 + Obsidian/Notion에 저장

## Stage 1: 주제 좁히기

사용자가 던진 주제가 너무 넓으면 좁히기 위해 짧게 질문:
- "MoE 동향" → "MoE 최신 동향 (2024-2026 위주)" 또는 "MoE 입문 / 실전 적용"
- "RAG" → "RAG 기초 / 고급 RAG 기법 / RAG vs Fine-tuning"

답이 모호하면 일반 입문~중급 수준으로 가정하고 진행.

## Stage 2: 조사

웹 검색 활용. 검색 쿼리는 영어 우선 (정보량 많음), 한국어 자료도 보조로.

조사 항목:
1. **핵심 개념**: 한 줄 정의 + 핵심 메커니즘
2. **왜 등장했나**: 해결하려는 문제, 이전 방식의 한계
3. **어떻게 동작하나**: 핵심 알고리즘/구조 (도식 가능)
4. **대표 사례 / 모델**: SOTA 또는 가장 영향력 있는 구현체
5. **장단점**: 객관적으로
6. **실전 적용 고려사항**: 데이터, 컴퓨팅, 비용
7. **참고문헌**: 논문 (저자, 연도, 제목, arXiv ID 또는 DOI)

출처 인용 원칙:
- 1차 출처(논문, 공식 블로그) 우선
- 2차 자료는 검증 가능한 것만
- 모든 인용은 (저자, 연도) + 링크

## Stage 3: HTML 노트 생성

템플릿: `~/.claude/templates/tech-note.html`

저장 경로: `/mnt/d/obsidian/Tech-Notes/{slug}/index.html`

함께 저장할 것:
- `/mnt/d/obsidian/Tech-Notes/{slug}/index.md` (Obsidian 노트용 마크다운 버전)

마크다운 노트 frontmatter:
```yaml
---
title: "{주제}"
date: 2026-MM-DD
type: tech-note
topic: {주제}
tags:
  - ai
  - {세부태그}
notion_url: "{Notion 페이지 URL}"
---
```

## Stage 4: Notion 업로드

회의록과 동일한 방식:
1. 사용자의 "기술노트" 부모 페이지 찾기 (또는 처음에 확인)
2. 새 페이지 생성
3. URL을 Obsidian 마크다운에 역참조

## 글쓰기 톤

**비전공자 이해 우선 원칙**:

| 좋은 예 | 나쁜 예 |
|---------|---------|
| "Transformer는 문장의 모든 단어가 서로 주목하는 구조다" | "Self-attention 메커니즘 기반의 sequence transduction model" |
| "MoE는 '전문가 여러 명 중 적합한 사람만 일하기'로 비유할 수 있다" | "Sparsely-activated MoE with top-k gating" |

전문 용어는 **처음 등장 시 1줄 설명**, 그 후로는 그냥 사용 OK.

**비유 사용 가이드**:
- 일상 사물에 빗대기 (도서관, 요리, 운동, 회사 조직)
- 비유는 정확성을 해치지 않는 범위 내에서
- "엄밀히는 다르지만" 같은 단서 명시

## HTML 노트 구조

`tech-note.html` 템플릿에 들어갈 섹션:
1. **한 줄 요약** (큰 글자)
2. **3분 요약** (비전공자용, 비유 위주)
3. **핵심 개념 다이어그램** (SVG로 그림)
4. **자세히 알아보기** (전문성 살린 설명, 접을 수 있게)
5. **실전 적용** (코드 스니펫 또는 의사코드)
6. **장단점 비교**
7. **참고문헌**

## 깊이 조절

사용자가 "심화"라고 하지 않는 한 기본은 **입문~중급**:
- 수식은 최소 (꼭 필요한 1-2개만)
- 코드는 의사코드 또는 짧은 Python 예시
- 길이: HTML 본문 기준 1500-2500자

"심화" 또는 "구현 가이드" 요청 시:
- 수식 포함 OK
- 실제 코드 (PyTorch/Transformers) 포함
- 5000자까지 확장

## 최종 보고

```
기술 노트 완성: {주제}
- Obsidian: /mnt/d/obsidian/Tech-Notes/{slug}/index.html
- Notion: https://notion.so/...

핵심 3가지: {bullet}
참고 논문 N개 정리
```
