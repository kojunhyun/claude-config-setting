---
name: sync-plugins
description: plugins.manifest 를 읽어 claude plugin marketplace add + install 을 자동 실행. 새 머신 셋업 후 또는 manifest 편집 후 호출.
---

# /sync-plugins

`$CLAUDE_CONFIG_DIR/plugins.manifest` 를 읽어 정의된 마켓플레이스와 플러그인을
현재 환경에 동기화한다. Bootstrap 안 거치고도 in-session 으로 가능.

## 동작

1. `$CLAUDE_CONFIG_DIR/plugins.manifest` 확인 (없으면 안내 후 종료)
2. 각 줄 파싱:
   - `market <source>` → `claude plugin marketplace add <source>`
   - `plugin <name@market>` → `claude plugin install <name@market>`
   - `#` 로 시작하는 줄과 빈 줄은 건너뜀
3. 결과를 `claude plugin list` 로 검증해 사용자에게 요약 보고
4. 새로 설치된 플러그인이 있으면 **Claude Code 재시작 필요** 안내

## 사용 예

```
/sync-plugins
```

manifest 편집 후:
```
# plugins.manifest 에서 hermes-CCC 의 # 제거
/sync-plugins
```

## 구현 메모

- Bash 로 실행. WSL/Linux/macOS 공통.
- Windows 사용자는 PowerShell 에서 `.\bootstrap.ps1` 재실행하거나 직접
  `claude plugin install ...` 수동 실행.
- 이미 등록된 마켓플레이스/플러그인은 에러 대신 경고만 띄움 (idempotent).
- 제거는 manifest 에서 라인을 주석처리해도 자동 uninstall 안 됨.
  명시적으로 `claude plugin uninstall <name>` 실행 필요.

## 동작 스크립트 (참고)

```bash
MANIFEST="${CLAUDE_CONFIG_DIR:-$HOME/claude-config}/plugins.manifest"
while IFS= read -r line; do
  line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  action="$(echo "$line" | awk '{print $1}')"
  arg="$(echo "$line" | awk '{print $2}')"
  case "$action" in
    market) claude plugin marketplace add "$arg" ;;
    plugin) claude plugin install "$arg" ;;
  esac
done < "$MANIFEST"
claude plugin list
```
