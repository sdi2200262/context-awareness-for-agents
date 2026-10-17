#!/usr/bin/env bash
# Common JSON hook transport for integrations with additionalContext support.
set -euo pipefail
# Monitoring failures must never use the native tool-blocking exit code 2.
trap 'exit 1' ERR
CONTEXT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT="$1"
INPUT="$(cat)"
SID="$(jq -er '.session_id // empty' <<< "$INPUT")" || exit 0
PROJECT="$(jq -r '.cwd // empty' <<< "$INPUT")"
if [[ -n "$PROJECT" ]]; then export CONTEXT_PROJECT_DIR="$PROJECT"; fi
TRANSCRIPT="$(jq -r '.transcript_path // empty' <<< "$INPUT")"
READING="$(bash "$CONTEXT_SRC/get-context.sh" "$ASSISTANT" "$SID" --json --transcript "$TRANSCRIPT")"
MESSAGE="$(printf '%s\n' "$READING" | bash "$CONTEXT_SRC/check-thresholds.sh" "$ASSISTANT")"
[[ -n "$MESSAGE" ]] || exit 0
jq -cn --arg message "$MESSAGE" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $message}}'
