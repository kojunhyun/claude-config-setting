#!/usr/bin/env bash
# tg-reset-hook.sh — UserPromptSubmit 훅. 들어온 프롬프트가 리셋 센티널이면 세션 종료.
# 텔레그램에서 "/새세션" "새세션" "세션리셋" 중 하나 -> 현재 세션 종료 -> 새 세션 기동.
#
# 검증 필요(터미널): 1) 텔레그램 메시지가 UserPromptSubmit 훅을 타는지
#   2) 이 빌드 훅 입력 JSON 키가 prompt 인지  3) block 출력 형식이 먹는지
set -u
INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("prompt",""))
except Exception:
    print("")' 2>/dev/null)"
case "$(printf '%s' "$PROMPT" | tr -d '[:space:]')" in
  "/새세션"|"새세션"|"세션리셋"|"/세션리셋")
    "$HOME/.claude/scripts/tg-reset.sh" >/dev/null 2>&1 &
    echo '{"decision":"block","reason":"새 세션으로 재시작합니다. 잠시 후 텔레그램에 새 세션이 붙습니다."}'
    exit 0 ;;
esac
exit 0
