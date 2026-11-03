#!/usr/bin/env bash
# 검사를 모두 통과해야만 커밋·푸시한다.  사용: tool/commit.sh "메시지"
set -euo pipefail
cd "$(dirname "$0")/.."
LOG="${TMPDIR:-/tmp}/check.log"
if ! bash tool/check.sh >"$LOG" 2>&1; then
  echo "검사 실패 — 커밋하지 않음"; grep -E "error|warning|info|Expected|Actual|\[E\]|Formatted|Changed" "$LOG" | head -20; exit 1
fi
tail -1 "$LOG"
cd ..
git add -A
git commit -q -m "$1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01F7mUDPiBNSrzb64jZ9gqVQ"
git push -q origin "$(git branch --show-current)"
echo "커밋·푸시 완료"
