#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
# Both assistants share a project, session ID and state base, but not settings/state.
CLAUDE_LOG="$CLAUDE_CONFIG_DIR/projects/example/reading.jsonl"
CODEX_LOG="$CODEX_HOME/sessions/2026/10/17/rollout-fixture-reading.jsonl"
request 10 20 30 > "$CLAUDE_LOG"
codex_header reading > "$CODEX_LOG"
codex_request 50 20 10 60 >> "$CODEX_LOG"
export CLAUDE_SESSION_ID=reading CODEX_THREAD_ID=reading
for assistant in claude codex; do
  if [[ "$assistant" == claude ]]; then user="$CLAUDE_CONFIG_DIR/context-awareness"; else user="$CODEX_HOME/context-awareness"; fi
  project="$CONTEXT_PROJECT_DIR/.$assistant/context-awareness"
  mkdir -p "$user"
  printf 'custom = 200\n' > "$user/capacity.conf"
  "$BASH_BIN" "$ROOT/src/get-context.sh" "$assistant" --json | assert_json '.window_tokens == 200 and .used_tokens == 60'
  printf 'custom = 100\n' > "$project/capacity.conf"
  "$BASH_BIN" "$ROOT/src/get-context.sh" "$assistant" --json | assert_json '.window_tokens == 100 and .used_percentage == 60'
  printf 'custom = 300\n' > "$TMP/explicit.conf"
  CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" "$BASH_BIN" "$ROOT/src/get-context.sh" "$assistant" --json | assert_json '.window_tokens == 300 and .used_percentage == 20'
  jq -cn --arg dir "$TMP/state" --arg assistant "$assistant" \
    '{flag_dir:$dir,thresholds:[{percent:50,level:"test",message:($assistant+" reminder")}],repeat_mode:"once_per_tier_reset_on_compaction"}' > "$project/config.json"
done
printf 'custom = 120\n' > "$CONTEXT_PROJECT_DIR/.codex/context-awareness/capacity.conf"
"$BASH_BIN" "$ROOT/src/get-context.sh" claude --json | assert_json '.assistant == "claude" and .window_tokens == 100'
"$BASH_BIN" "$ROOT/src/get-context.sh" codex --json | assert_json '.assistant == "codex" and .window_tokens == 120'
# Install an unchanged package in a spaced path and execute registered commands.
PACKAGE="$TMP/installed plugin"
mkdir -p "$PACKAGE"
cp -R "$ROOT/src" "$ROOT/claude" "$ROOT/codex" "$ROOT/.claude-plugin" "$ROOT/.codex-plugin" "$PACKAGE/"
export CLAUDE_PLUGIN_ROOT="$PACKAGE" PLUGIN_ROOT="$PACKAGE"
for assistant in claude codex; do
  manifest="$PACKAGE/.$assistant-plugin/plugin.json"
  skills="$(jq -r '.skills[0]' "$manifest")"
  hooks="$(jq -r '.hooks' "$manifest")"
  [[ -f "$PACKAGE/$skills/get-my-context/SKILL.md" ]]
  [[ "$skills" == "./$assistant/skills/" ]]
  command="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$PACKAGE/$hooks")"
  if [[ "$assistant" == claude ]]; then transcript="$CLAUDE_LOG"; else transcript="$CODEX_LOG"; fi
  input="$(jq -cn --arg cwd "$CONTEXT_PROJECT_DIR" --arg path "$transcript" '{session_id:"reading",cwd:$cwd,transcript_path:$path}')"
  printf '%s\n' "$input" | "$BASH_BIN" -c "$command" | assert_json ".hookSpecificOutput.additionalContext == \"$assistant reminder\""
  [[ -z "$(printf '%s\n' "$input" | "$BASH_BIN" -c "$command")" ]]
  # Hook cwd must override the parent shell's project, never choose by dotdirs.
  CONTEXT_PROJECT_DIR="$TMP/wrong project" "$BASH_BIN" -c "$command" <<< "$input" > "$TMP/out"
  [[ ! -s "$TMP/out" ]]
  printf 'invalid\n' > "$CONTEXT_PROJECT_DIR/.$assistant/context-awareness/capacity.conf"
  code=0
  "$BASH_BIN" -c "$command" <<< "$input" > "$TMP/out" 2> "$TMP/err" || code=$?
  [[ "$code" == 1 && ! -s "$TMP/out" && -s "$TMP/err" ]]
  [[ -z "$(printf '%s\n' '{}' | "$BASH_BIN" -c "$command")" ]]
done
[[ -f "$TMP/state/context-awareness-$(id -u)/claude/reading.json" ]]
[[ -f "$TMP/state/context-awareness-$(id -u)/codex/reading.json" ]]
# Claude's skill still preprocesses directly without a model shell call.
printf 'custom = 100\n' > "$CONTEXT_PROJECT_DIR/.claude/context-awareness/capacity.conf"
command="$(sed -n 's/^!`\(.*\)`$/\1/p' "$PACKAGE/claude/skills/get-my-context/SKILL.md")"
"$BASH_BIN" -c "$command --json" | assert_json '.used_tokens == 60 and .window_tokens == 100'
if "$BASH_BIN" "$ROOT/src/get-context.sh" '../claude' reading > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
if CODEX_THREAD_ID='' "$BASH_BIN" "$ROOT/src/get-context.sh" codex > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
[[ -z "$(find "$PACKAGE" -type l)" ]]
printf 'ok: assistant coexistence, native configuration and installed transports\n'

# A new reader can be added without modifying shared dispatch or calculations.
mkdir -p "$PACKAGE/fixture-agent"
cat > "$PACKAGE/fixture-agent/integration.sh" <<'ADAPTER'
context_adapter_scope() {
  CONTEXT_PROJECT_CONFIG="$CONTEXT_PROJECT_DIR/.fixture/context-awareness"
  CONTEXT_USER_CONFIG="$CONTEXT_PROJECT_DIR/.fixture-user/context-awareness"
}
context_adapter_session() { printf '%s\n' fixture-session; }
context_adapter_read() {
  printf '%s\n' '{"used_tokens":65,"measurement_source":"fixture","measurement_basis":"fixture","model":null,"measured_at":null,"segment":"initial"}'
}
ADAPTER
printf 'custom = 100\n' > "$PACKAGE/fixture-agent/capacity.conf"
"$BASH_BIN" "$PACKAGE/src/get-context.sh" fixture-agent --json |
  assert_json '.assistant == "fixture-agent" and .session_id == "fixture-session" and .used_tokens == 65 and .used_percentage == 65'
[[ "$(jq -r .version "$PACKAGE/.claude-plugin/plugin.json")" == "$(jq -r .version "$PACKAGE/.codex-plugin/plugin.json")" ]]
printf 'ok: extension contract without shared-code changes\n'
