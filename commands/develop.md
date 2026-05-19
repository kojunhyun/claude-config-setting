---
name: develop
description: 풀스택 멀티 에이전트 코드개발 파이프라인 시작. 6개 Lead가 협업해 설계→구현→QA→git push까지.
---

# /develop {프로젝트 설명}

사용자가 던진 프로젝트 설명을 받아 `dev-pipeline` 스킬을 즉시 실행한다.

## 동작

1. `dev-pipeline` 스킬 로드
2. 사용자 입력을 `01-requirements.md` 후보로 처리
3. Stage 1 (요구사항 분석)부터 자동 시작
4. 게이트(Stage 3, 6)에서만 사용자에게 묻기

## 사용 예

```
/develop 사내 직원 휴가 관리 시스템. 슬랙 연동, 관리자 대시보드, 휴가 잔여일 자동 계산
```

```
/develop ./프로젝트브리프.md
```

(파일 경로 형태도 OK — 파일을 읽어 requirements 시드로 사용)

## 주의

- 처음 사용 시 git remote URL을 묻습니다 (Stage 6에서)
- 완료까지 길게는 1-2시간 소요. 중간 게이트에서 사용자 확인 필요
- 산출물은 `$PROJECTS_DIR/{slug}/` 에 누적
