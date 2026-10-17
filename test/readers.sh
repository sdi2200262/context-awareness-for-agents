#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/example/reading.jsonl"
read_context() { "$BASH_BIN" "$ROOT/src/get-context.sh" claude reading --json "$@"; }
# 2 + 9507 + 25892 = 35401. Requests and duplicate streamed records are not added.
request 100 20 30 > "$TRANSCRIPT"
request 2 9507 25892 >> "$TRANSCRIPT"
request 2 9507 25892 >> "$TRANSCRIPT"
printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":999999}}}' '{partial' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 35401 and .measurement_source == "request"'
printf '%s\n' '{"type":"system","subtype":"compact_boundary","uuid":"boundary-one","compactMetadata":{"postTokens":4773}}' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 4773 and .measurement_source == "compaction"'
request 10 20 30 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 60 and .measurement_source == "request"'
request -1 0 0 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == null and .measurement_source == "request"'
printf '%s\n' '{"type":"system","subtype":"compact_boundary","uuid":"boundary-two"}' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == null and .used_percentage == null'
request 0 0 0 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 0 and .used_percentage == 0'
read_context --transcript "$TMP/absent" | assert_json '.used_tokens == null'
printf 'ok: readings and compaction\n'


# Codex totals already include cached input and output; never sum requests.
TRANSCRIPT="$CODEX_HOME/sessions/2026/10/17/rollout-fixture-reading.jsonl"
read_context() { "$BASH_BIN" "$ROOT/src/get-context.sh" codex reading --json "$@"; }
codex_header reading > "$TRANSCRIPT"
printf '%s\n' '{"type":"turn_context","payload":{"model":"fixture-codex"}}' >> "$TRANSCRIPT"
codex_request 1000 500 20 1020 >> "$TRANSCRIPT"
codex_request 2000 1500 30 2030 >> "$TRANSCRIPT"
codex_request 2000 1500 30 2030 >> "$TRANSCRIPT"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":null}}' '{partial' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 2030 and .measurement_source == "request" and .model == "fixture-codex" and .window_tokens == null and .measurement_basis == "codex_latest_total"'
printf '%s\n' '{"type":"compacted","timestamp":"boundary-one","payload":{"message":"summary"}}' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == null and .segment == "boundary-one"'
codex_request 0 0 0 4773 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 4773 and .measurement_source == "native_estimate" and .segment == "boundary-one"'
codex_request 6000 4000 200 6200 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 6200 and .measurement_source == "request" and .segment == "boundary-one"'
codex_request 0 0 0 -1 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == null'
codex_request 0 0 0 0 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 0'
printf '%s\n' '{"type":"event_msg","timestamp":"rollback-one","payload":{"type":"thread_rolled_back","num_turns":1}}' >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == null and .segment == "rollback:rollback-one"'
codex_request 500 100 10 510 >> "$TRANSCRIPT"
read_context | assert_json '.used_tokens == 510'
read_context --transcript "$TMP/absent" | assert_json '.used_tokens == null'
"$BASH_BIN" "$ROOT/src/get-context.sh" codex different --json --transcript "$TRANSCRIPT" | assert_json '.used_tokens == null'
cp "$TRANSCRIPT" "$CODEX_HOME/sessions/2026/10/17/rollout-duplicate-reading.jsonl"
read_context | assert_json '.used_tokens == null'
rm "$CODEX_HOME/sessions/2026/10/17/rollout-duplicate-reading.jsonl"
# A rate-limit-only update never turns unknown into zero.
codex_header empty > "$TMP/empty.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":null}}' >> "$TMP/empty.jsonl"
"$BASH_BIN" "$ROOT/src/get-context.sh" codex empty --json --transcript "$TMP/empty.jsonl" | assert_json '.used_tokens == null'
printf 'ok: Codex totals, compaction, rollback and session identity\n'

# Large older segments must not leak readings or producer broken-pipe diagnostics.
for assistant in claude codex; do
  large="$TMP/$assistant-large.jsonl"
  if [[ "$assistant" == claude ]]; then
    request 999 0 0 > "$large"
    jq -cn '{type:"noise",text:("x" * 200000)}' >> "$large"
    printf '%s\n' '{"type":"system","subtype":"compact_boundary","uuid":"large-boundary","compactMetadata":{"postTokens":123}}' >> "$large"
  else
    codex_header reading > "$large"
    codex_request 999 0 0 999 >> "$large"
    jq -cn '{type:"noise",text:("x" * 200000)}' >> "$large"
    printf '%s\n' '{"type":"compacted","timestamp":"large-boundary"}' >> "$large"
    codex_request 0 0 0 123 >> "$large"
  fi
  "$BASH_BIN" "$ROOT/src/get-context.sh" "$assistant" reading --json --transcript "$large" > "$TMP/out" 2> "$TMP/err"
  assert_json '.used_tokens == 123 and .segment == "large-boundary"' < "$TMP/out"
  [[ ! -s "$TMP/err" ]]
done
printf 'ok: large prior segments and clean output\n'
