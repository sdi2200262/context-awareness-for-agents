#!/usr/bin/env bash
# Convert Claude's hook input to a reading, then format threshold instructions.
set -euo pipefail
# A monitoring error must not return Claude's tool-blocking exit code 2.
trap 'exit 1' ERR
CLAUDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat)"
SID="$(jq -er '.session_id // empty' <<< "$INPUT")" || exit 0
PROJECT="$(jq -r '.cwd // empty' <<< "$INPUT")"
if [[ -n "$PROJECT" ]]; then export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PROJECT}"; fi
TRANSCRIPT="$(jq -r '.transcript_path // empty' <<< "$INPUT")"
READING="$(bash "$CLAUDE_DIR/../src/get-context.sh" claude "$SID" --json --transcript "$TRANSCRIPT")"
MESSAGE="$(printf '%s\n' "$READING" | bash "$CLAUDE_DIR/../src/check-thresholds.sh" claude)"
[[ -n "$MESSAGE" ]] || exit 0
jq -cn --arg message "$MESSAGE" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $message}}'
