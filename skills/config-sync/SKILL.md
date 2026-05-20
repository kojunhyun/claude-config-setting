---
name: config-sync
description: |
  $CLAUDE_CONFIG_DIR 에서 git pull --rebase 후 스킬/agent/command 변경 사항을
  요약 출력. 새 스킬 인식하려면 Claude Code 재시작 필요함을 안내.
  매일 수동/자동 호출용. 충돌 발생 시 안전하게 abort 하고 사용자에게 보고.
  Use this skill when the user runs `/config-sync` or scheduled daily.
when_to_use:
  - "/config-sync 명령으로 시작"
  - "config 동기화, 최신 받기, 셋업 업데이트 키워드"
  - "schedule 로 매일 호출됨"
---

# Config Sync — Claude Config 머신 간 동기화

## 목적

이 머신의 `$CLAUDE_CONFIG_DIR` 를 origin/main 과 일치시켜 다른 머신에서 push 된
스킬/agent/command/hook 변경을 받는다. 변경 요약 + 재시작 안내까지.

## 입력

- 기본: 인자 없음 (origin/main 받기)
- 옵션: `/config-sync --check` — pull 안 하고 변경 사항만 미리보기

## Stage 1: 환경 점검

```bash
REPO="${CLAUDE_CONFIG_DIR:-$HOME/claude-config}"
if [ ! -d "$REPO/.git" ]; then
  echo "[config-sync] ❌ $REPO 는 git repo 아님 — 종료"
  exit 1
fi
cd "$REPO"
```

## Stage 2: 작업 트리 안전성 확인

```bash
# 미커밋 변경 있으면 abort (충돌 위험)
if [ -n "$(git status --porcelain)" ]; then
  echo "[config-sync] ⚠️  미커밋 변경 있음:"
  git status --short
  echo
  echo "[config-sync] git stash 또는 commit 후 재시도 권장"
  echo "  $ git stash && /config-sync && git stash pop"
  exit 1
fi
```

## Stage 3: Fetch + 비교

```bash
echo "[config-sync] fetching..."
git fetch origin main --quiet

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "[config-sync] ✅ 이미 최신 ($(git log -1 --oneline))"
  exit 0
fi

# 변경 미리보기
echo "[config-sync] 새 commit:"
git log --oneline "$LOCAL..$REMOTE" | sed 's/^/  /'
echo
echo "[config-sync] 변경된 config 파일:"
git diff --name-status "$LOCAL..$REMOTE" -- \
        skills/ agents/ commands/ hooks/ plugins.manifest paths.env CLAUDE.md | \
  awk '{flag=$1; path=$2;
        p=(flag=="A")?"  + ":(flag=="M")?"  ~ ":(flag=="D")?"  - ":"  ? ";
        print p path}'
```

`--check` 모드면 여기까지만 출력하고 종료.

## Stage 4: Pull (rebase)

```bash
echo
echo "[config-sync] pulling..."
if git pull --rebase --autostash origin main; then
  echo "[config-sync] ✅ 동기화 완료"
  # post-merge hook 이 이미 변경 요약 출력했을 것
else
  echo "[config-sync] ❌ rebase 충돌 — 사용자 개입 필요"
  echo "  1) 충돌 파일 수정: $(git diff --name-only --diff-filter=U)"
  echo "  2) git add <파일>"
  echo "  3) git rebase --continue"
  echo "  또는 git rebase --abort 로 취소"
  exit 1
fi
```

## Stage 5: Plugin 동기화 (옵션)

`plugins.manifest` 가 바뀌었다면 새 플러그인이 추가됐을 가능성:

```bash
if echo "$CHANGED_FILES" | grep -q "plugins.manifest"; then
  echo
  echo "[config-sync] plugins.manifest 변경됨 — /sync-plugins 실행 권장"
fi
```

## Stage 6: 재시작 안내

```bash
echo
echo "[config-sync] 새 스킬/agent/command 적용하려면 Claude Code 재시작 필요"
echo "  현재 세션에서 호출했다면 exit 후 claude 다시 실행"
```

## 무인 실행 (`claude -p`) 호환

비대화형에서도 동작:
- 사용자 입력 요청 금지
- 충돌 시 exit 1 (cron 로그에 남게)
- 성공 시 짧은 한 줄 보고

## D — 매일 자동 실행 등록

각 머신에서 한 번만:

```
/schedule create config-pull "30 7 * * *" run /config-sync
```

또는 시스템 cron:

```cron
30 7 * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-sync" >> ~/.claude/logs/config-sync.log 2>&1
```

> 시간은 출근 전 (예: 07:30). 충돌 발생 시 사용자가 일과 시작할 때 발견할 수
> 있도록.

## 안전 정책

- 미커밋 변경 있으면 무조건 abort (lost work 방지)
- rebase 충돌 시 자동 해결 시도 X — 사용자가 직접
- `--autostash` 옵션으로 임시 변경은 자동 보존되긴 함
- 절대 force push 안 함
- origin/main 외 브랜치는 안 건드림
