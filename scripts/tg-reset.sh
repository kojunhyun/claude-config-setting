#!/usr/bin/env bash
# tg-reset.sh — 현재 Claude 세션을 종료시켜 claude-loop 가 '새 세션'을 띄우게 한다.
PIDFILE="$HOME/.claude/.tg-claude-pid"
if [ -f "$PIDFILE" ]; then
  pid="$(cat "$PIDFILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null && echo "reset: claude(pid=$pid) 종료 시그널 전송 -> 새 세션 기동 예정"
  else
    echo "reset: 기록된 pid($pid)가 살아있지 않음"
  fi
else
  echo "reset: PID 파일 없음 - claude-loop.sh 로 실행 중이 아님"
fi
