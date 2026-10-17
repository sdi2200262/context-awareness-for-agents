#!/usr/bin/env bash
# Common JSON hook transport for integrations with additionalContext support.
set -Eeuo pipefail
# Monitoring failures must never use the native tool-blocking exit code 2.
trap 'exit 1' ERR
CONTEXT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CONTEXT_SRC/check-thresholds.sh"
ASSISTANT="$1"
INPUT="$(cat)"
SID="$(jq -er '.session_id // empty' <<< "$INPUT")" || exit 0
PROJECT="$(jq -r '.cwd // empty' <<< "$INPUT")"
if [[ -n "$PROJECT" ]]; then export CONTEXT_PROJECT_DIR="$PROJECT"; fi
context_scope "$ASSISTANT"
# Resolve one configuration snapshot before any measurement or state access.
CONFIG="$(context_threshold_config)"
context_hooks_enabled "$CONFIG" || exit 0
context_session "$SID"
TRANSCRIPT="$(jq -r '.transcript_path // empty' <<< "$INPUT")"
MEASUREMENT="$(context_adapter_read "$SID" "$TRANSCRIPT")"
READING="$(context_report "$MEASUREMENT" "$SID" json)"
MESSAGE="$(context_check_thresholds "$READING" "$CONFIG")"
[[ -n "$MESSAGE" ]] || exit 0
SUMMARY="$(context_format_reading "$READING")"
GUIDANCE="Use these usage details internally to plan your work. Report usage only when the user asks. If the capacity preset or token limit differs from the context window or compaction limit stated for this session, correct the capacity config and rerun get-my-context before using this percentage."
jq -cn --arg message "$MESSAGE" --arg summary "$SUMMARY" --arg guidance "$GUIDANCE" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: ($message + "\n\n" + $summary + "\n" + $guidance)}}'
