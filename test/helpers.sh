#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/context-tests-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONFIG_DIR="$TMP/claude user" CODEX_HOME="$TMP/codex user"
export CONTEXT_PROJECT_DIR="$TMP/project space" CLAUDE_PROJECT_DIR="$TMP/project space"
unset CONTEXT_CAPACITY_CONFIG CONTEXT_THRESHOLDS_CONFIG CLAUDE_SESSION_ID CODEX_THREAD_ID
mkdir -p "$CLAUDE_CONFIG_DIR/projects/example" "$CODEX_HOME/sessions/2026/10/17" \
  "$CONTEXT_PROJECT_DIR/.claude/context-awareness" "$CONTEXT_PROJECT_DIR/.codex/context-awareness"
assert_json() { jq -e "$1" >/dev/null || { printf 'FAIL: %s\n' "$1" >&2; exit 1; }; }
request() {
  jq -cn --argjson input "$1" --argjson creation "$2" --argjson cache "$3" \
    '{type:"assistant",message:{model:"fixture",usage:{input_tokens:$input,cache_creation_input_tokens:$creation,cache_read_input_tokens:$cache,output_tokens:9999}}}'
}
codex_header() { jq -cn --arg sid "$1" '{type:"session_meta",payload:{id:$sid}}'; }
codex_request() {
  jq -cn --argjson input "$1" --argjson cache "$2" --argjson output "$3" --argjson total "$4" \
    '{type:"event_msg",timestamp:"fixture-time",payload:{type:"token_count",info:{total_token_usage:{total_tokens:9999999},model_context_window:9999999,last_token_usage:{input_tokens:$input,cached_input_tokens:$cache,output_tokens:$output,total_tokens:$total}}}}'
}
