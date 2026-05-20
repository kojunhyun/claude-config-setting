---
name: setup-status
description: 새 PC 셋업 시 사람이 해야 할 항목들의 현재 상태를 한 화면에 점검·체크리스트 출력. git/SSH/Notion/Obsidian/MCP 통합.
---

# /setup-status

`setup-status` 스킬을 실행한다. 이 머신의 셋업 상태를 한 화면 체크리스트로 출력.

## 점검 항목

1. paths.env / paths.local.env 로드
2. Git identity (개인 / 회사 자동 전환)
3. SSH keys 존재
4. ~/.ssh/config host alias (github.com / gitlab.aixera.net)
5. **SSH 공개키 외부 등록 (수동 필수)** — URL + 키 + 테스트 명령
6. 회사 폴더 존재
7. Notion target 별 token 동작 (실제 API 호출 검증)
8. Obsidian vault 경로
9. CLAUDE_MACHINE_ID, WEEKLY_LEADER
10. 플러그인 활성 상태 (ECC 등)

## 사용 예

새 PC 셋업 직후:
```
/setup-status
```

기존 머신에서도 가끔 상태 확인:
```
/setup-status
```

## 출력

각 항목 ✅ / ⏳ / ❌ 로 표시. ⏳ 항목은 **그대로 복사해서 실행할 수 있는 명령/URL** 제공.
