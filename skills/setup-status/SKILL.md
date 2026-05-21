---
name: setup-status
description: |
  새 PC 셋업 시 사람이 해야 할 항목들의 현재 상태를 한 화면에 점검·체크리스트 출력.
  git identity, SSH keys, ssh config host alias, work folder, gitconfig includeIf,
  Notion token, Obsidian vault, MCP/플러그인까지.
  Use this skill when the user runs `/setup-status` or asks "what's left to set up".
when_to_use:
  - "/setup-status 명령으로 시작"
  - "새 PC 셋업 점검, 셋업 체크리스트 키워드"
  - "지금까지 뭐 해야 하는지 확인 요청"
---

# Setup Status — 셋업 체크리스트

## 목적

새 머신에서 `git clone + ./bootstrap.sh` 후 **사람이 직접 해야 할 작업**들을
한 화면에 표시. 자동으로 처리되지 않는 외부 시스템(GitHub, GitLab, Notion 웹)
관련 작업 + paths.local.env 의 빈 필드 안내.

## 동작

다음 항목들을 순서대로 점검하고 **체크리스트** 형태로 출력. 각 항목마다:
- ✅ 자동 처리됨 / 사용자 액션 불필요
- ⏳ 사용자 액션 필요 — 정확한 명령 또는 URL 안내

### 1. paths.env / paths.local.env 로드 상태

```bash
[ -f "$CLAUDE_CONFIG_DIR/paths.env" ]       && echo "✅ paths.env"        || echo "❌ paths.env 없음"
[ -f "$CLAUDE_CONFIG_DIR/paths.local.env" ] && echo "✅ paths.local.env"  || echo "❌ paths.local.env 없음 → ./bootstrap.sh 재실행"
```

### 2. Git identity (개인/회사)

```bash
# 개인 (현재 위치 = $CLAUDE_CONFIG_DIR, 회사 폴더 아님)
EXPECTED_EMAIL="${GIT_PERSONAL_EMAIL:-}"
ACTUAL_EMAIL=$(git config user.email)
[ "$ACTUAL_EMAIL" = "$EXPECTED_EMAIL" ] && echo "✅ 개인 identity ($ACTUAL_EMAIL)" \
  || echo "⏳ 개인 identity 다름: 기대 [$EXPECTED_EMAIL], 실제 [$ACTUAL_EMAIL]
    → ~/.gitconfig 에 [user] section 추가:
        [user]
            name = $GIT_PERSONAL_NAME
            email = $GIT_PERSONAL_EMAIL"

# 회사 (work dir 안에서 임시 init 해서 검사)
WORK_DIR="${GIT_WORK_DIR:-/mnt/d/Aixera}"
TMP=$(mktemp -d "$WORK_DIR/.setup-check.XXXX") && (cd "$TMP" && git init -q)
ACTUAL_WORK=$(cd "$TMP" && git config user.email)
rm -rf "$TMP"
[ "$ACTUAL_WORK" = "$GIT_WORK_EMAIL" ] && echo "✅ 회사 identity 자동 전환 ($ACTUAL_WORK)" \
  || echo "⏳ 회사 identity 자동 전환 안 됨
    → ~/.gitconfig 에 추가:
        [includeIf \"gitdir:${WORK_DIR}/\"]
            path = ~/.gitconfig-work
    → ~/.gitconfig-work 작성:
        [user]
            email = $GIT_WORK_EMAIL"
```

### 3. SSH keys

```bash
for kname in "$GIT_PERSONAL_KEY_NAME" "$GIT_WORK_KEY_NAME"; do
  [ -z "$kname" ] && continue
  kpath="$HOME/.ssh/$kname"
  if [ -f "$kpath" ]; then
    echo "✅ SSH key: $kpath"
  else
    echo "⏳ SSH key 없음: $kpath
      → ./bootstrap.sh 재실행 (자동 생성됨)
      → 또는 수동: ssh-keygen -t ed25519 -f $kpath -N \"\""
  fi
done
```

### 4. ~/.ssh/config host alias

```bash
# paths.env 의 GIT_PERSONAL_HOSTS, GIT_WORK_HOSTS 콤마 분리해서
# 각 host 가 ~/.ssh/config 에 등록되어 있는지 확인
check_ssh_host() {
  local host="$1" kname="$2"
  if grep -qE "^Host\s+${host}\b" "$HOME/.ssh/config" 2>/dev/null; then
    echo "✅ ssh config: $host"
  else
    echo "⏳ ssh config 에 $host 미등록
      → ~/.ssh/config 에 추가:
          Host $host
              HostName $host
              User git
              IdentityFile ~/.ssh/$kname
              IdentitiesOnly yes"
  fi
}

IFS=, read -ra PH <<< "$GIT_PERSONAL_HOSTS"
IFS=, read -ra WH <<< "$GIT_WORK_HOSTS"
for h in "${PH[@]}"; do check_ssh_host "$h" "$GIT_PERSONAL_KEY_NAME"; done
for h in "${WH[@]}"; do check_ssh_host "$h" "$GIT_WORK_KEY_NAME"; done
```

### 5. SSH 공개키 → 외부 등록 (수동 필수)

```bash
# 공개키 출력 + 어디 등록해야 하는지 안내
for tag in PERSONAL WORK; do
  KN_VAR="GIT_${tag}_KEY_NAME"; HOSTS_VAR="GIT_${tag}_HOSTS"
  KEY_NAME="${!KN_VAR}"
  HOSTS="${!HOSTS_VAR}"
  # 비활성 (HTTPS+PAT 만 쓰는 경우 등) 이면 skip
  [ -z "$KEY_NAME" ] || [ -z "$HOSTS" ] && continue
  pub="$HOME/.ssh/${KEY_NAME}.pub"
  [ ! -f "$pub" ] && continue
  echo
  echo "⏳ $tag 공개키 — 아래 호스트에 등록 필요 (브라우저로):"
  for h in $(echo "$HOSTS" | tr ',' ' '); do
    case "$h" in
      github.com)             echo "    https://github.com/settings/keys" ;;
      gitlab.com)             echo "    https://gitlab.com → Preferences → SSH Keys" ;;
      *)                      echo "    https://$h (User Settings → SSH Keys)" ;;
    esac
  done
  echo "    공개키:"
  echo "        $(cat "$pub")"
  # 연결 테스트 명령 안내
  for h in $(echo "${!HOSTS_VAR}" | tr ',' ' '); do
    echo "    테스트:  ssh -T git@$h"
  done
done
```

### 6. 회사 폴더

```bash
WORK_DIR="${GIT_WORK_DIR:-/mnt/d/Aixera}"
[ -d "$WORK_DIR" ] && echo "✅ 회사 폴더: $WORK_DIR" \
  || echo "⏳ 회사 폴더 없음: $WORK_DIR
    → mkdir -p $WORK_DIR"
```

### 7. Notion targets — token / 부모 페이지

```bash
TARGETS="${CLAUDE_LOG_NOTION_TARGETS:-default}"
for t in $(echo "$TARGETS" | tr ',' ' '); do
  T=$(echo "$t" | tr '[:lower:]' '[:upper:]')
  TOKEN_VAR="CLAUDE_LOG_NOTION_${T}_TOKEN"
  PARENT_VAR="CLAUDE_LOG_NOTION_${T}_PARENT"
  TOKEN="${!TOKEN_VAR}"
  PARENT="${!PARENT_VAR}"
  if [ -z "$TOKEN" ]; then
    echo "⏳ Notion [$t] token 없음
      → https://www.notion.so/profile/integrations 에서 integration 만들고
        secret 복사 → paths.local.env 에 추가:
            $TOKEN_VAR=\"secret_xxx...\""
  else
    # 실제 동작 검증 (선택)
    code=$(curl -sS -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $TOKEN" -H "Notion-Version: 2022-06-28" \
      https://api.notion.com/v1/users/me)
    [ "$code" = "200" ] && echo "✅ Notion [$t] token 동작 (parent=\"$PARENT\")" \
      || echo "⏳ Notion [$t] token 동작 안 함 (HTTP $code) — 재발급 또는 권한 확인"
  fi
done
```

### 8. Obsidian vault

```bash
[ -d "${OBSIDIAN_DIR:-$HOME/Obsidian}" ] && echo "✅ Obsidian vault: $OBSIDIAN_DIR" \
  || echo "⏳ Obsidian vault 없음: $OBSIDIAN_DIR — vault 만들기 또는 동기화 설정 필요"
```

### 9. CLAUDE_MACHINE_ID + WEEKLY_LEADER

```bash
[ -n "${CLAUDE_MACHINE_ID:-}" ] && echo "✅ MACHINE_ID = $CLAUDE_MACHINE_ID" \
  || echo "⏳ MACHINE_ID 비어있음 → paths.local.env 편집"

case "${CLAUDE_WEEKLY_LEADER:-}" in
  true|1|yes|y) echo "✅ 이 머신 = weekly LEADER" ;;
  *)            echo "ℹ️  이 머신은 비-leader (정상, leader 머신은 따로)" ;;
esac
```

### 10. 플러그인 + MCP

```bash
claude plugin list 2>/dev/null | grep -q "ecc@ecc.*enabled" \
  && echo "✅ ECC 플러그인 설치/활성" \
  || echo "⏳ ECC 플러그인 미설치 → /sync-plugins"

# MCP 인증 (Notion token 검증으로 갈음. 별도 MCP 필요하면 사용자가 /mcp 확인)
```

## 출력 형식

전체를 한 화면에 보기 좋게:

```
================================================================
Claude Config — Setup Status (jhko-mac-mini)
================================================================
[paths]
  ✅ paths.env, paths.local.env 로드됨

[git identity]
  ✅ 개인 identity (skykjh200@naver.com)
  ✅ 회사 identity 자동 전환 (jhko@aixera.co.kr in /mnt/d/Aixera/)

[ssh keys]
  ✅ ~/.ssh/id_ed25519
  ✅ ~/.ssh/id_ed25519_aixera

[ssh config]
  ✅ ssh config: github.com
  ✅ ssh config: gitlab.aixera.net

[external pubkey registration]
  ⏳ PERSONAL 공개키 — 등록 필요:
        URL:  https://github.com/settings/keys
        키:   ssh-ed25519 AAAA...
        test: ssh -T git@github.com
  ⏳ WORK 공개키 — 등록 필요:
        URL:  https://gitlab.aixera.net → SSH Keys
        키:   ssh-ed25519 AAAA...
        test: ssh -T git@gitlab.aixera.net

[work folder]
  ✅ /mnt/d/Aixera

[notion]
  ⏳ personal token 없음 → paths.local.env 에 CLAUDE_LOG_NOTION_PERSONAL_TOKEN
  ⏳ work     token 없음 → paths.local.env 에 CLAUDE_LOG_NOTION_WORK_TOKEN

[obsidian]
  ✅ /mnt/d/obsidian

[machine]
  ✅ MACHINE_ID = jhko-mac-mini
  ✅ weekly LEADER

[plugins]
  ✅ ECC 플러그인 설치/활성

================================================================
요약: 2 todo (notion tokens), 2 외부 등록 (github + gitlab 공개키)
================================================================
```

## 무인 실행

`claude -p "/setup-status"` 호환. 출력만 하므로 부작용 없음.
오류 항목이 있으면 exit code 1 (스크립트에서 게이팅 가능).
