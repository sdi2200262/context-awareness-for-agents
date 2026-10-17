#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
PACKAGE="$TMP/installed plugin"
mkdir -p "$PACKAGE"
cp -R "$ROOT/src" "$ROOT/claude" "$ROOT/codex" "$ROOT/.claude-plugin" "$ROOT/.codex-plugin" "$PACKAGE/"
export CLAUDE_PLUGIN_ROOT="$PACKAGE" PLUGIN_ROOT="$PACKAGE"
export CONTEXT_READER_CALLS="$TMP/reader-calls"
# Test instrumentation exists only in the temporary installed package.
for assistant in claude codex; do
  cat >> "$PACKAGE/$assistant/integration.sh" <<'ADAPTER'
context_adapter_read() {
  printf 'read\n' >> "$CONTEXT_READER_CALLS"
  if [[ -n "${CONTEXT_TEST_CHANGE_CONFIG:-}" ]]; then
    printf '{"hooks":false}\n' > "$CONTEXT_TEST_CHANGE_CONFIG"
  fi
  bash "$CONTEXT_INTEGRATION/read-context.sh" "$@"
}
ADAPTER
done
request 10 20 30 > "$CLAUDE_CONFIG_DIR/projects/example/reading.jsonl"
CODEX_LOG="$CODEX_HOME/sessions/2026/10/17/rollout-fixture-reading.jsonl"
codex_header reading > "$CODEX_LOG"
codex_request 50 20 10 60 >> "$CODEX_LOG"
export CLAUDE_SESSION_ID=reading CODEX_THREAD_ID=reading
write_config() {
  jq -cn --arg message "$2" --arg dir "$TMP/state" \
    '{hooks:true,flag_dir:$dir,repeat_mode:"every_turn",thresholds:[{percent:0,level:"test",message:$message}]}' > "$1"
}
state_snapshot() {
  if [[ -d "$TMP/state" ]]; then
    find "$TMP/state" -print | sort
    find "$TMP/state" -type f -exec cksum {} \; | sort
  fi
}
check_skip() {
  local before after
  before="$(state_snapshot)"
  : > "$CONTEXT_READER_CALLS"
  run_hook > "$TMP/out" 2> "$TMP/err"
  after="$(state_snapshot)"
  [[ ! -s "$CONTEXT_READER_CALLS" && ! -s "$TMP/out" && ! -s "$TMP/err" && "$before" == "$after" ]]
}
check_error() {
  local code=0
  : > "$CONTEXT_READER_CALLS"
  run_hook > "$TMP/out" 2> "$TMP/err" || code=$?
  [[ "$code" == 1 && ! -s "$CONTEXT_READER_CALLS" && ! -s "$TMP/out" && -s "$TMP/err" ]]
}
for assistant in claude codex; do
  if [[ "$assistant" == claude ]]; then user="$CLAUDE_CONFIG_DIR/context-awareness"; transcript="$CLAUDE_CONFIG_DIR/projects/example/reading.jsonl"; else user="$CODEX_HOME/context-awareness"; transcript="$CODEX_LOG"; fi
  project="$CONTEXT_PROJECT_DIR/.$assistant/context-awareness"
  mkdir -p "$user"
  input="$(jq -cn --arg cwd "$CONTEXT_PROJECT_DIR" --arg path "$transcript" '{session_id:"reading",cwd:$cwd,transcript_path:$path}')"
  hook="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$PACKAGE/$assistant/hooks.json")"
  run_hook() { "$BASH_BIN" -c "$hook" <<< "$input"; }
  # Global both -> project skill-only, before capacity or reader/state access.
  write_config "$user/config.json" global
  printf '{"hooks":false}\n' > "$project/config.json"
  printf 'invalid\n' > "$project/capacity.conf"
  check_skip
  # Skill still reads normally; hook mode does not gate the common reader.
  printf 'custom = 100\n' > "$project/capacity.conf"
  "$BASH_BIN" "$PACKAGE/src/get-context.sh" "$assistant" --json | assert_json '.used_tokens == 60 and .used_percentage == 60'
  [[ -s "$CONTEXT_READER_CALLS" ]]
  if [[ "$assistant" == claude ]]; then
    skill_command="$(claude_skill_command)"
    "$BASH_BIN" -c "$skill_command --json" | assert_json '.used_tokens == 60'
  fi
  # Global skill-only -> project both; project config replaces the user file.
  printf '{"hooks":false}\n' > "$user/config.json"
  write_config "$project/config.json" project
  run_hook | assert_json '(.hookSpecificOutput.additionalContext | startswith("project\n\n"))'
  # Omitted hooks keeps existing configurations enabled.
  jq 'del(.hooks)' "$project/config.json" > "$TMP/legacy.json"
  cp "$TMP/legacy.json" "$project/config.json"
  run_hook | assert_json '(.hookSpecificOutput.additionalContext | startswith("project\n\n"))'
  # Turning monitoring off preserves existing files/locks and does no reading.
  printf '{"hooks":false}\n' > "$project/config.json"
  check_skip
  rm "$project/config.json"
  check_skip
  # Empty tiers are also an early opt-out, even with hooks explicitly true.
  printf '{"hooks":true,"thresholds":[]}\n' > "$project/config.json"
  check_skip
  # Explicit override wins over project settings in either direction.
  write_config "$project/config.json" project
  printf '{"hooks":false}\n' > "$TMP/explicit.json"
  CONTEXT_THRESHOLDS_CONFIG="$TMP/explicit.json" check_skip
  printf '{"hooks":false}\n' > "$project/config.json"
  write_config "$TMP/explicit.json" explicit
  CONTEXT_THRESHOLDS_CONFIG="$TMP/explicit.json" run_hook | assert_json '(.hookSpecificOutput.additionalContext | startswith("explicit\n\n"))'
  CONTEXT_THRESHOLDS_CONFIG="$TMP/missing.json" check_error
  # Validate configuration before the reader and keep native errors nonblocking.
  for value in null '"false"' 0 '{}' '[]'; do
    printf '{"hooks":%s}\n' "$value" > "$project/config.json"
    check_error
  done
  printf '{invalid\n' > "$project/config.json"
  check_error
  write_config "$project/config.json" invalid-session
  saved_input="$input"
  for sid in 'bad/id' 'a b' 'a.b'; do
    input="$(jq --arg sid "$sid" '.session_id = $sid' <<< "$saved_input")"
    check_error
  done
  input="$saved_input"
  # A malformed state base is rejected before measurement too.
  jq '.flag_dir = "relative/state"' "$project/config.json" > "$TMP/relative.json"
  CONTEXT_THRESHOLDS_CONFIG="$TMP/relative.json" check_error
  # Enabling hooks does not merge thresholds from the disabled user config.
  for config in '{}' '{"hooks":true}' '{"hooks":true,"thresholds":null}'; do
    printf '%s\n' "$config" > "$project/config.json"
    check_error
    [[ "$(cat "$TMP/err")" == *'enabled reminders require a thresholds array'* ]]
  done
  printf '{"hooks":false,"thresholds":"unused","repeat_mode":"unused"}\n' > "$project/config.json"
  check_skip
  printf 'not a measurement\n' | CONTEXT_THRESHOLDS_CONFIG="$project/config.json" "$BASH_BIN" "$PACKAGE/src/check-thresholds.sh" "$assistant" > "$TMP/out"
  [[ ! -s "$TMP/out" ]]
  # One hook uses the config it selected, even if the file changes during reading.
  write_config "$project/config.json" snapshot
  CONTEXT_TEST_CHANGE_CONFIG="$project/config.json" run_hook | assert_json '(.hookSpecificOutput.additionalContext | startswith("snapshot\n\n"))'
  check_skip
  # Disabling and re-enabling does not reset a once-per-tier reminder.
  write_config "$TMP/once.json" once
  jq '.repeat_mode = "once_per_tier" | .thresholds[0].level = "once"' "$TMP/once.json" > "$project/config.json"
  run_hook | assert_json '(.hookSpecificOutput.additionalContext | startswith("once\n\n"))'
  cp "$project/config.json" "$TMP/saved.json"
  printf '{"hooks":false}\n' > "$project/config.json"
  check_skip
  cp "$TMP/saved.json" "$project/config.json"
  [[ -z "$(run_hook)" ]]
  printf 'ok: %s skill-only mode, overrides, snapshot and preserved state\n' "$assistant"
done
[[ -z "$("$BASH_BIN" -c 'source "$1/src/check-thresholds.sh"' bash "$ROOT")" ]]
