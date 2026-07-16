# 텔레그램에서 원격 /new (새 세션) 트리거 - 설계 & 설치

## 한 줄
Claude Code 의 진짜 `/new`(세션 리셋)는 클라이언트(터미널) 동작이라 텔레그램 브릿지가 직접 못 한다.
그래서 **supervisor 루프 + 자기-종료 트리거**로 우회한다: 텔레그램에서 센티널을 보내면 현재 세션을
종료시키고, 루프가 즉시 새 `claude` 세션을 띄워 원격 /new 효과를 낸다.

## 구성요소 (이 폴더)
- `claude-loop.sh` - claude 를 루프로 실행(세션 종료 -> 자동으로 새 세션 기동)
- `tg-reset.sh` - 기록된 PID로 현재 세션에 TERM 전송(종료 -> 루프가 새 세션)
- `tg-reset-hook.sh` - UserPromptSubmit 훅. 센티널("/새세션" 등) 감지 시 tg-reset 실행 + 프롬프트 차단

## 설치 (터미널에서)
1. 스크립트를 `~/.claude/scripts/` 에서 접근 가능하게: `ln -sf "$CLAUDE_CONFIG_DIR/scripts" ~/.claude/scripts` (이미 있으면 생략)
2. 실행권한: `chmod +x "$CLAUDE_CONFIG_DIR"/scripts/*.sh`
3. `settings.json` 의 hooks.UserPromptSubmit 에 등록:
   ```json
   { "hooks": { "UserPromptSubmit": [
       { "hooks": [ { "type": "command", "command": "~/.claude/scripts/tg-reset-hook.sh" } ] }
   ] } }
   ```
4. 평소 `claude` 대신 루프로 실행: `~/.claude/scripts/claude-loop.sh ~/00_Project/02_Haruflow`

## 사용
- 텔레그램에서 `새세션`(또는 `/새세션`, `세션리셋`) 전송 -> 현재 세션 종료 -> 몇 초 뒤 새 세션이 붙음.
- 정지: `touch ~/.claude/.tg-loop-stop` 후 세션 종료.

## 반드시 터미널에서 검증 (이 세션에서 테스트 불가 - 이 세션이 죽음)
1. TTY: `claude &`(백그라운드) 상태에서 텔레그램 조작 정상인지. 터미널 직접 입력도 필요하면 FOREGROUND 대안 + pgrep 종료로 조정.
2. 훅 경유: 텔레그램 메시지가 UserPromptSubmit 훅을 타는지.
3. 훅 JSON 스키마: 입력 키가 prompt 인지, block 출력이 먹는지.
4. PID 타게팅: tg-reset.sh 가 맞는 claude 만 종료하는지(여러 claude 실행 시 주의).

## 보안
- 봇에 메시지 보낼 수 있는 사람 = 세션 리셋 가능. access.json 허용목록으로 발신자 제한됨.
  페어링 추가는 절대 채팅으로 승인하지 말 것.

## 한계 (정직)
- 이 방식은 '진짜' 세션 교체라 컨텍스트가 실제로 비워지고 비용도 떨어진다(행동적 리셋과 다름).
- 단 self-kill + 재기동이라 위 4가지 환경 검증이 끝나야 신뢰 가능. 미검증 상태 상시 사용 금지.
