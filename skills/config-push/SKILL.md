---
name: config-push
description: |
  $CLAUDE_CONFIG_DIR 의 변경을 자동으로 commit + push. secret 패턴 자동 차단,
  의미있는 commit 메시지 자동 생성, rebase 충돌 시 안전 abort.
  매시간 schedule 로 호출되도록 설계 — 작업 중간에도 자동 동기화.
  Use this skill when the user runs `/config-push` or scheduled hourly.
when_to_use:
  - "/config-push 명령으로 시작"
  - "config 자동 push, 변경 사항 올리기 키워드"
  - "schedule 로 주기 자동 호출됨"
---

# Config Push — Claude Config 자동 commit + push

## 목적

다른 머신이 자동 pull (`/config-sync` schedule) 로 받을 수 있도록, 작업한 머신에서
**push 가 자동으로 발생**하게 함. 사용자가 push 잊어도 다른 머신이 옛 버전 안 보게.

## 안전 정책 (먼저 읽기)

이 스킬은 **자동 commit + push 라는 위험한 작업**을 수행. 다음 안전장치가 반드시
동작해야 함:

1. **Secret scan** — secret 패턴 발견 시 즉시 abort
2. **gitignore 신뢰** — `paths.local.env`, `.claude.json`, `.credentials.json` 등
   이미 ignored. 추가로 staging diff 검사
3. **빈 변경 무시** — 변경 없으면 commit 안 함 (no-op)
4. **충돌 시 abort** — rebase 충돌이면 push 안 함
5. **사용자 staging 보존** — 사용자가 의도적으로 staging 한 게 있으면 그것도 같이
   commit (사용자 의도로 간주)

## Stage 0: 머신 가드 (multi-machine 안전)

`/schedule` 이 모든 머신에서 트리거되더라도 paths.env 의 정책을 보고
허용 머신에서만 실제 실행. 시스템 cron 이라면 이미 머신 격리되지만
이중 안전망.

```bash
ALLOWED="${SCHEDULE_PUSH_MACHINES:-}"
MID="${CLAUDE_MACHINE_ID:-$(hostname | tr '[:upper:]' '[:lower:]')}"
if [ -n "$ALLOWED" ]; then
  if ! echo ",$ALLOWED," | grep -q ",$MID,"; then
    echo "[config-push] $MID 는 SCHEDULE_PUSH_MACHINES 목록에 없음 ($ALLOWED) — skip"
    exit 0
  fi
fi
```

빈값(`SCHEDULE_PUSH_MACHINES=""`) 이면 모든 머신 허용 (가드 비활성).
특정 머신만 push 자동화하려면 paths.env 에 콤마 구분 목록.

## Stage 1: 환경 점검

```bash
REPO="${CLAUDE_CONFIG_DIR:-$HOME/claude-config}"
[ -d "$REPO/.git" ] || { echo "[config-push] ❌ git repo 아님"; exit 1; }
cd "$REPO"

# 변경 있나?
if [ -z "$(git status --porcelain)" ]; then
  # 미 push commit 만 있을 수도
  if git fetch origin main --quiet && [ "$(git rev-list HEAD ^origin/main --count)" -gt 0 ]; then
    echo "[config-push] 미푸시 commit 발견 — push 만 시도"
    NEED_PUSH=1
  else
    echo "[config-push] ✅ 변경 없음, 이미 origin/main 동기화"
    exit 0
  fi
fi
```

## Stage 2: Secret Scan (필수)

**모든 변경 파일을 secret 패턴으로 점검**. 발견 시 abort.

```bash
# 검사 대상: tracked modified + untracked (gitignored 는 자동 제외)
TARGETS=$(git status --porcelain | awk '$1 !~ /^!/ {print $2}')

SECRETS_FOUND=0
SECRET_PATTERNS='secret_[a-zA-Z0-9_]{16,}|Bearer\s+[a-zA-Z0-9_\-\.]{20,}|sk-ant-[a-zA-Z0-9_\-]{20,}|sk_live_[a-zA-Z0-9]+|ghp_[a-zA-Z0-9]{30,}|glpat-[a-zA-Z0-9_\-]{20,}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|aws_secret_access_key|"password"\s*:\s*"[^"]+"|api[_-]?key\s*[=:]\s*['"'"'"][a-zA-Z0-9_\-]{20,}'

for f in $TARGETS; do
  [ -f "$f" ] || continue
  if grep -E -l "$SECRET_PATTERNS" "$f" >/dev/null 2>&1; then
    echo "❌ secret pattern in: $f"
    SECRETS_FOUND=$((SECRETS_FOUND+1))
  fi
done

if [ $SECRETS_FOUND -gt 0 ]; then
  echo
  echo "[config-push] ⚠️  secret pattern 발견 — push abort"
  echo "  해결: 해당 파일을 .gitignore 에 추가하거나, secret 을"
  echo "        paths.local.env 같은 ignored 파일로 옮기기"
  exit 1
fi
```

> secret pattern 은 false-positive 가 있을 수 있음. 정상 콘텐츠가 잘못 매치되면
> 그 파일을 `.gitignore` 에 추가하거나 패턴을 좁히기.

## Stage 3: Staging

```bash
# 모든 변경 staging (gitignored 는 자동 제외됨)
git add -A

# 검증: secret 이 staging 에 들어갔는지 한 번 더 (paranoid check)
if git diff --cached | grep -E "$SECRET_PATTERNS" >/dev/null 2>&1; then
  echo "[config-push] ⚠️  staging 후 secret 재검출 — abort"
  git reset
  exit 1
fi
```

## Stage 4: 자동 Commit 메시지 생성

변경 종류 기반으로 의미있는 메시지:

```bash
ADDED=$(git diff --cached --name-status | awk '$1=="A"' | wc -l)
MODIFIED=$(git diff --cached --name-status | awk '$1=="M"' | wc -l)
DELETED=$(git diff --cached --name-status | awk '$1=="D"' | wc -l)

# 변경된 영역 파악
AREAS=$(git diff --cached --name-only | awk -F/ '
  /^skills\// {print "skills"}
  /^agents\// {print "agents"}
  /^commands\// {print "commands"}
  /^hooks\// {print "hooks"}
  /^templates\// {print "templates"}
  /paths\.env$/ {print "config"}
  /plugins\.manifest$/ {print "plugins"}
  /^SETUP\.md$/ {print "docs"}
  /^CLAUDE\.md$/ {print "docs"}
' | sort -u | paste -sd ',' -)

MID="${CLAUDE_MACHINE_ID:-$(hostname)}"
SUMMARY=""
[ $ADDED   -gt 0 ] && SUMMARY="$SUMMARY +$ADDED"
[ $MODIFIED -gt 0 ] && SUMMARY="$SUMMARY ~$MODIFIED"
[ $DELETED  -gt 0 ] && SUMMARY="$SUMMARY -$DELETED"

MSG="auto: ${AREAS:-misc}${SUMMARY} (from ${MID})

Files changed:
$(git diff --cached --name-status | sed 's/^/  /')

Auto-committed by config-push on $(date -Iseconds)"

git commit -m "$MSG" --quiet || { echo "[config-push] commit 실패"; exit 1; }
echo "[config-push] ✅ committed: ${AREAS:-misc}${SUMMARY}"
```

## Stage 5: Pull (rebase) — 안전 push 전 사전 동기화

```bash
echo "[config-push] origin 과 동기화 (rebase)..."
if ! git pull --rebase --autostash origin main; then
  echo "[config-push] ❌ rebase 충돌 — 사용자 개입 필요"
  echo "  push abort. 다음을 수동 실행:"
  echo "    cd $REPO"
  echo "    git status  # 충돌 파일 확인"
  echo "    # 충돌 해결 후"
  echo "    git add <파일>"
  echo "    git rebase --continue"
  echo "    git push"
  exit 1
fi
```

## Stage 6: Push

```bash
if git push origin main; then
  echo "[config-push] ✅ pushed → origin/main"
  echo "  다른 머신은 /config-sync (또는 매일 07:30 schedule) 로 받음"
else
  echo "[config-push] ❌ push 실패 (네트워크 / 권한 / non-fast-forward)"
  echo "  다음 routine 호출 때 재시도"
  exit 1
fi
```

## 무인 실행 (`claude -p`) 호환

비대화형 안전 동작:
- 사용자 입력 요청 금지
- 변경 없으면 exit 0 (조용히)
- 안전장치 위반 시 exit 1 + 로그
- secret 발견은 exit 1 + 명확한 이유

## D — 매시간 자동 등록 (각 머신)

```
/schedule create config-push "5 * * * *" run /config-push
```

매시간 5분 (`00:05`, `01:05`, `02:05`...) 에 변경 있으면 자동 push.

또는 시스템 cron:
```cron
5 * * * *  cd $CLAUDE_CONFIG_DIR && claude -p "/config-push" >> ~/.claude/logs/config-push.log 2>&1
```

**주기 권장**:
- 매시간 (기본) — 적당히 적극적
- 매 30분 (`*/30 * * * *`) — 더 빠른 sync
- 일과 끝 (`0 18 * * *`) — 하루 한 번만

## 사용자 수동 push 와의 공존

이 스킬은 사용자 수동 push 와 **공존**. 사용자가:
- 직접 `git commit -m "의미있는 메시지" && git push` 했으면 → 그대로 origin 에 있음
- 다음 config-push 호출 시 → 변경 없으면 no-op

즉 자동 push 가 켜져 있어도 사용자가 좋은 commit 메시지로 직접 push 하는 워크플로
그대로 유지 가능. 자동은 사용자가 잊을 때의 안전망.

## 알려진 위험 (사용자 인지 필요)

1. **미완성 작업도 push** — 자동이라 진행 중인 reaction 이 push 될 수 있음.
   완전 안전하려면 별도 브랜치에서 작업 후 main 으로 merge 패턴.
2. **잘못된 commit 메시지** — auto 라벨이 붙어 의미 추정만. 의식적 메시지가
   필요한 큰 변경은 사용자가 먼저 수동 commit 권장.
3. **충돌 빈도 증가 가능** — 여러 머신 자동 push 가 충돌하면 늦은 쪽이 abort.
   당장 영향은 없지만 다음 routine 호출 때 재시도.
4. **Secret false-negative** — secret pattern 이 새 형태면 못 잡을 수도.
   진짜 secret 은 항상 `paths.local.env` 등 gitignored 에 두는 게 원칙.

## Off 스위치

자동 push 끄려면:
- 해당 머신에서 `/schedule delete config-push`
- 또는 시스템 cron 에서 해당 줄 삭제

수동 `/config-push` 는 그대로 사용 가능.
