---
name: sync-plugins
description: |
  $CLAUDE_CONFIG_DIR/plugins.manifest 를 읽어 `claude plugin marketplace add`
  + `claude plugin install` 자동 실행. bootstrap 의 plugin sync 블록과 동일 로직.
  manifest 편집 후 또는 새 머신 셋업 직후 호출.
  Use this skill when the user runs `/sync-plugins`.
when_to_use:
  - "/sync-plugins 명령으로 시작"
  - "plugin 동기화, 매니페스트 적용 키워드"
  - "plugins.manifest 편집 직후"
---

# Sync Plugins — plugins.manifest 적용

## 목적

`plugins.manifest` 의 선언적 목록을 현재 머신에 반영. 머신 간 plugin 일관성 보장.

## 동작

```bash
REPO="${CLAUDE_CONFIG_DIR:-$HOME/claude-config}"
MANIFEST="$REPO/plugins.manifest"

if [ ! -f "$MANIFEST" ]; then
  echo "[sync-plugins] ❌ $MANIFEST 없음 — 종료"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "[sync-plugins] ❌ claude CLI 없음 — npm i -g @anthropic-ai/claude-code 먼저"
  exit 1
fi

echo "[sync-plugins] manifest: $MANIFEST"

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  line="${raw_line%$'\r'}"
  line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac

  action="$(echo "$line" | awk '{print $1}')"
  arg="$(echo "$line" | awk '{print $2}')"
  [ -z "$arg" ] && continue

  case "$action" in
    market)
      echo "[sync-plugins]   market add: $arg"
      claude plugin marketplace add "$arg" 2>&1 | sed 's/^/[sync-plugins]     /' || \
        echo "[sync-plugins]     WARN: marketplace add 실패 (이미 있을 수 있음)"
      ;;
    plugin)
      echo "[sync-plugins]   plugin install: $arg"
      claude plugin install "$arg" 2>&1 | sed 's/^/[sync-plugins]     /' || \
        echo "[sync-plugins]     WARN: install 실패 (이미 설치되어 있을 수 있음)"
      ;;
    *)
      echo "[sync-plugins]   WARN: 알 수 없는 action '$action' — 스킵"
      ;;
  esac
done < "$MANIFEST"

echo
echo "[sync-plugins] 동기화 완료. 현재 설치된 플러그인:"
claude plugin list 2>&1 | sed 's/^/  /' | head -30
echo
echo "[sync-plugins] 새 플러그인 적용하려면 Claude Code 재시작 필요"
```

## Manifest 문법 (한 줄당 한 액션)

```
# 주석
market <github-repo-or-url>     # 마켓플레이스 등록
plugin <name>@<market>          # 플러그인 설치
```

## 무인 실행 호환

`claude -p "/sync-plugins"` 비대화형 호환. 출력만, 부작용은 plugin 설치/마켓 추가.

## 제거

manifest 에서 라인 주석 처리는 *재설치 차단* 만. 자동 uninstall 안 함.
명시적 제거:

```bash
claude plugin uninstall <name>
claude plugin marketplace remove <market>
```

## 트러블슈팅

| 증상 | 해결 |
|---|---|
| `claude plugin` 명령 없다 | `npm i -g @anthropic-ai/claude-code` 후 재시도 |
| 마켓플레이스 add 실패 | 이미 등록된 경우 — `claude plugin marketplace list` 로 확인 후 skip 가능 |
| install 실패 (인증) | claude.ai 로그인 안 됨 — `claude login` 먼저 |
| 토큰 비용 큰 ECC | `claude plugin details ecc` 로 always-on 비용 확인 후 disable: `claude plugin disable ecc` |
