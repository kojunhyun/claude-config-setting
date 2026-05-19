---
name: dev-pipeline
description: |
  AI 개발 팀장 관점의 풀스택 코드개발 파이프라인. 프로젝트 개요만 받으면
  Design/Frontend/Backend/AI/Security/QA 6개 Lead subagent를 오케스트레이션해
  설계→병렬구현→통합검증→git push→HTML 리포트까지 자동 수행.
  Use this skill when the user runs `/develop` or asks to build a new project
  from a brief description (e.g. "쇼핑몰 추천 시스템 만들어줘", "사내 챗봇 프로토타입").
when_to_use:
  - "/develop 명령으로 시작"
  - "프로젝트를 처음부터 만들어달라는 요청"
  - "팀 단위 코드개발 작업"
default_tech_stack:
  frontend: "React + TypeScript + Tailwind CSS"
  backend: "FastAPI (Python 3.11+)"
  ai: "PyTorch + HuggingFace Transformers + LangChain"
  db: "PostgreSQL"
  infra: "Docker Compose (개발)"
---

# Dev Pipeline — 풀스택 멀티 에이전트 개발 워크플로우

이 스킬은 AI 개발 팀장 관점에서 6개의 Lead Agent를 조율해 프로젝트를 끝까지 끌고 가는 표준 파이프라인이다.

## 운영 원칙

- **사용자 = 팀장**. 오케스트레이터(메인 oh 세션) = 비서이자 조정자
- **Lead 6명**은 각각 독립 컨텍스트(subagent)로 동작. Lead 간 정보 교환은 orchestrator가 중계
- **게이트**: 사용자 확인이 필요한 두 지점이 있음 — Stage 3(통합 계획 승인), Stage 6(git push 직전)
- **작업물 디렉토리**: `/mnt/d/00_Project/{project-slug}/`
- **권한 모드**: `full_auto` — 파일 생성/수정 자유롭게, 단 게이트는 반드시 사용자에게

## 6단계 파이프라인

### Stage 1: 요구사항 분석 (orchestrator 단독)

사용자가 던진 한 줄 설명을 구조화한다.

작업:
1. 핵심 명사/동사 추출 → 프로젝트 슬러그 자동 생성 (예: "쇼핑몰 추천 시스템" → `shopmall-recsys`)
2. 모호한 부분이 있으면 `ask_user_question`으로 **최대 3개 질문** (그 이상은 인내심 깎임)
3. 산출물: `outputs/{slug}/01-requirements.md`

질문 가이드라인 (필요할 때만):
- 사용자/규모 (예상 동시접속, 데이터 양)
- 배포 목표 (PoC인지 실서비스인지)
- 외부 의존성 (특정 API/SaaS 사용 여부)

### Stage 2: 병렬 설계 (6개 Lead 동시 호출)

각 Lead에게 동일한 `01-requirements.md`를 던지고 각자 영역 설계서를 받는다.

```
orchestrator → spawn(design-lead, frontend-lead, backend-lead,
                     ai-lead, security-lead, qa-lead)
              [병렬]
```

각 Lead의 출력 위치:
- `outputs/{slug}/02-design/design.md`
- `outputs/{slug}/02-design/frontend.md`
- `outputs/{slug}/02-design/backend.md`
- `outputs/{slug}/02-design/ai.md`
- `outputs/{slug}/02-design/security.md`
- `outputs/{slug}/02-design/qa.md`

**중요**: Lead에게 전달할 컨텍스트는 압축해서 보낸다. 전체 대화 히스토리 X, requirements.md만 첨부. Lead의 시스템 프롬프트는 `~/.openharness/agents/*-lead.md` 참조.

### Stage 3: 통합 계획 회의 (orchestrator 통합) — 🚪 게이트 1

각 Lead의 산출물을 종합해 통합 계획서를 만든다.

작업:
1. 인터페이스 충돌 검출
   - Frontend가 기대하는 API 시그니처 vs Backend가 제공하는 시그니처
   - AI 모델 출력 포맷 vs Backend가 받는 포맷
2. 일정 추정 (전체 추정 + 의존성 그래프)
3. 위험 요소 정리 (Security Lead가 표시한 핵심 이슈 우선)

산출물: `outputs/{slug}/03-plan.md` — 다음 항목 포함:
- 프로젝트 개요 1단락
- 기술 스택 결정 (default와 다른 경우 이유 명시)
- 모듈 간 인터페이스 정의 (API 스펙, 데이터 스키마)
- WBS (작업 분해, 의존성 그래프)
- 위험 요소 + 완화 방안
- 일정 추정

🚪 **사용자에게 계획서 보여주고 명시적 승인을 받는다**. "이대로 진행할까요? 수정사항 있으면 알려주세요."

승인 후에만 Stage 4로 진행.

### Stage 4: 병렬 구현 (각 Lead가 코드 작성)

승인된 plan.md를 기준으로 각 Lead가 자기 영역 코드를 작성한다.

```
orchestrator → spawn(각 Lead, 구현 모드)
                   ↓
            Lead가 필요시 팀원 agent 또 spawn
```

작업 디렉토리: `outputs/{slug}/code/`
표준 구조:
```
code/
├── frontend/        ← Frontend Lead 담당
├── backend/         ← Backend Lead 담당
├── ai/              ← AI Lead 담당
├── docker-compose.yml
├── README.md
└── .gitignore
```

각 Lead는 자기 폴더 안에서만 작업한다. 다른 폴더 침범 금지. 인터페이스 파일(예: `shared/types.ts`)은 orchestrator가 중재.

**진행상황 기록**: 각 Lead가 완료할 때마다 `outputs/{slug}/progress.md`에 append.

### Stage 5: QA 통합 검증 (QA Lead 주도)

QA Lead가 전체를 받아 실제 동작을 검증한다.

작업:
1. `docker-compose up -d` 실행 시도
2. 빌드 에러 → 해당 Lead에게 fix 요청
3. 기본 통합 테스트 작성 + 실행
4. 보안 체크리스트 확인 (Security Lead 산출물 기준)
5. 산출물: `outputs/{slug}/05-qa-report.md`

실패 시: 해당 Lead 재호출 → 수정 → 다시 검증. 최대 3회 루프.

### Stage 6: Git push + 최종 HTML 리포트 — 🚪 게이트 2

🚪 **git remote URL 사용자에게 묻기** (또는 `outputs/{slug}/.git-remote` 파일에 미리 있으면 사용):
```
어느 레포에 push할까요?
예: git@gitlab.com:myteam/shopmall-recsys.git
```

작업:
1. `code/` 디렉토리에서 `git init`
2. 초기 커밋 (`git commit -m "feat: initial implementation by oh dev-pipeline"`)
3. `git remote add origin <URL>`
4. `git push -u origin main` (실패 시 사용자에게 자격증명/권한 확인 요청)
5. 최종 HTML 리포트 생성: `outputs/{slug}/REPORT.html`
   - 템플릿: `~/.openharness/templates/dev-summary.html`
   - 핵심 항목만: 개요 / 스택 / 아키텍처 다이어그램(SVG) / 주요 결정사항 / 미해결 이슈

산출물 트리 최종:
```
outputs/{slug}/
├── 01-requirements.md
├── 02-design/*.md
├── 03-plan.md
├── code/ (실제 동작 코드, git pushed)
├── 05-qa-report.md
├── progress.md
└── REPORT.html              ← 사용자가 주로 보는 파일
```

## 토큰 관리 전략

이 워크플로우는 컨텍스트 폭발 위험이 가장 큰 작업이다. 다음 원칙 엄수:

1. **Lead에게 전달할 때 풀 히스토리 금지** — 해당 단계 input 파일만 첨부
2. **Lead 응답 받으면 요약본만 컨텍스트에 유지** — 원본은 디스크에
3. **Stage 간 transition마다** 이전 단계 raw 출력은 컨텍스트에서 빼고 파일 참조만 유지
4. v0.1.6 Auto-Compaction이 자동으로 처리하지만, 명시적으로 200턴 한도를 의식할 것

## 사용자와의 상호작용 톤

- 사용자는 AI 팀장 — 기술 디테일에 휘말리지 말 것
- 의사결정 필요한 지점만 간결하게 보고
- Lead들의 내부 토론은 사용자에게 노출 안 함 (요약된 결과만)
- 게이트(Stage 3, 6)에서는 "이대로 진행할까요?" 한 줄로 묻기

## 실패 모드 대응

- **Lead가 막힘**: 해당 Lead의 컨텍스트 리셋 + plan.md만 재공급
- **빌드 실패 3회 연속**: orchestrator가 사용자에게 보고 + plan 재검토 제안
- **API 키/시크릿 필요**: 절대 자동 생성 금지. 사용자에게 환경변수 가이드 제공
- **git push 실패**: 자격증명 가이드만 안내, 임의의 토큰 입력 시도 금지
