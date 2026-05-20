---
name: config-push
description: $CLAUDE_CONFIG_DIR 의 변경을 자동 commit + push. secret 패턴 자동 차단, 의미있는 메시지 자동 생성. 매시간 schedule 자동 호출 가능.
---

# /config-push

`config-push` 스킬을 실행한다.

## 동작

1. `$CLAUDE_CONFIG_DIR` working tree 점검 (변경 없으면 no-op)
2. **Secret pattern scan** — secret_*, Bearer, sk-ant-*, ghp_*, glpat-*,
   PRIVATE KEY, api_key 등 발견 시 즉시 abort
3. 모든 변경 staging (gitignored 는 자동 제외)
4. staging 에 secret 재검증 (paranoid check)
5. 의미있는 commit 메시지 자동 생성 (변경 영역 + 추가/수정/삭제 카운트)
6. `git pull --rebase --autostash` 로 origin 동기화
7. `git push` → 충돌/실패 시 abort + 명확한 안내

## 사용 예

```
/config-push    # 지금 즉시 push (수동)
```

## 매시간 자동 등록 (각 머신)

```
/schedule create config-push "5 * * * *" run /config-push
```

또는 시스템 cron:

```cron
5 * * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-push" >> ~/.claude/logs/config-push.log 2>&1
```

## ⚠️ 위험 인지

자동 push 는 다음 위험 동반:
- 미완성 작업도 push 됨 (의식적 분기/PR 패턴 권장 시)
- auto 라벨 commit 메시지 — 의식적 메시지 필요한 큰 변경은 사용자 수동 commit
- secret pattern false-negative 가능 — 진짜 secret 은 항상 `paths.local.env` 등 gitignored 에

자동 끄기:
```
/schedule delete config-push
```

수동 `/config-push` 는 계속 사용 가능.

## 사용자 수동 push 와의 공존

직접 `git commit && git push` 한 후엔 다음 자동 호출 시 변경 없어서 no-op.
즉 자동은 사용자가 잊었을 때의 안전망 역할.
