---
name: config-sync
description: $CLAUDE_CONFIG_DIR git pull 후 스킬/agent 변경 요약. 다른 머신에서 push 된 업데이트를 받아오는 가장 안전한 흐름.
---

# /config-sync [--check]

`config-sync` 스킬을 실행한다.

## 동작

1. `$CLAUDE_CONFIG_DIR` 의 git working tree 안전성 확인 (미커밋 변경 abort)
2. `git fetch origin main` → 로컬과 비교
3. 새 commit 목록 + 변경된 skills/agents/commands/hooks 요약 표시
4. `git pull --rebase --autostash` 로 받기
5. post-merge hook 이 추가 변경 요약 출력
6. Claude Code 재시작 필요 시 안내

## 옵션

- `--check` — pull 안 하고 어떤 변경이 있는지 미리보기만

## 사용 예

```
/config-sync          # 매일 한 번, 또는 다른 머신에서 push 봤을 때
/config-sync --check  # 어떤 변경 있는지 먼저 보기
```

## 자동 등록 (각 머신에서 한 번)

매일 출근 시간 전 자동 동기화:

```
/schedule create config-pull "30 7 * * *" run /config-sync
```

또는 시스템 cron:

```cron
30 7 * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-sync" >> ~/.claude/logs/config-sync.log 2>&1
```

## 충돌 시

미커밋 변경 있거나 rebase 충돌 발생 시 안전하게 abort 후 안내. 사용자가 직접:
- `git stash` 또는 `git commit` 후 재시도
- rebase 충돌이면 `git status` 로 충돌 파일 확인 → 수정 → `git add` → `git rebase --continue`
