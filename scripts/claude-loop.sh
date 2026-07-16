#!/usr/bin/env bash
# claude-loop.sh — Claude Code 를 루프로 실행해서, 세션이 끝나면 '새 세션'이 자동 기동.
# 텔레그램에서 리셋을 트리거하면(tg-reset.sh) 현재 세션이 종료되고 -> 새 세션이 떠서
# 원격 "/new" 효과를 낸다.
#
# 사용:  ./claude-loop.sh [작업디렉토리]
#   예)  ~/.claude/scripts/claude-loop.sh ~/00_Project/02_Haruflow
#
# 검증 필요(터미널): claude 를 백그라운드로 띄우면 터미널 직접 입력(TTY)이 안 갈 수 있다.
#   텔레그램으로만 조작하면 문제없음. 터미널 입력도 쓰려면 FOREGROUND 대안(아래) 사용.
set -u
WORKDIR="${1:-$PWD}"
STATE="$HOME/.claude"
STOP="$STATE/.tg-loop-stop"
PIDFILE="$STATE/.tg-claude-pid"
mkdir -p "$STATE"
cd "$WORKDIR" || { echo "작업디렉토리 없음: $WORKDIR"; exit 1; }
trap 'rm -f "$PIDFILE"' EXIT

while true; do
  echo "[claude-loop] $(date '+%F %T') - 새 세션 시작 ($WORKDIR)"
  claude &
  cpid=$!
  echo "$cpid" > "$PIDFILE"
  wait "$cpid"
  rm -f "$PIDFILE"
  if [ -f "$STOP" ]; then rm -f "$STOP"; echo "[claude-loop] 정지 플래그 -> 종료"; break; fi
  echo "[claude-loop] 세션 종료됨 -> 새 세션 재기동(원격 /new)"
  sleep 1
done

# --- FOREGROUND 대안(터미널 입력도 필요할 때) ---
# while true; do
#   claude
#   [ -f "$STOP" ] && { rm -f "$STOP"; break; }
# done
