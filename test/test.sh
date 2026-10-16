#!/usr/bin/env bash
# Deterministic behavior checks; native Claude invocation is tested separately.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/context-tests-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONFIG_DIR="$TMP/user config" CLAUDE_PROJECT_DIR="$TMP/project space"
unset CONTEXT_CAPACITY_CONFIG CONTEXT_THRESHOLDS_CONFIG
mkdir -p "$CLAUDE_CONFIG_DIR/projects/example" "$CLAUDE_PROJECT_DIR/.claude/context-awareness"
TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/example/reading.jsonl"
read_context() { "$BASH_BIN" "$ROOT/src/get-context.sh" claude reading --json "$@"; }
assert_json() { jq -e "$1" >/dev/null || { printf 'FAIL: %s\n' "$1" >&2; exit 1; }; }
request() {
  jq -cn --argjson input "$1" --argjson creation "$2" --argjson cache "$3" \
    '{type:"assistant",message:{model:"fixture",usage:{input_tokens:$input,cache_creation_input_tokens:$creation,cache_read_input_tokens:$cache,output_tokens:9999}}}'
}
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

# Capacity and precedence are exercised through the public command.
USER_CONFIG="$CLAUDE_CONFIG_DIR/context-awareness"
PROJECT_CONFIG="$CLAUDE_PROJECT_DIR/.claude/context-awareness"
mkdir -p "$USER_CONFIG"
printf 'custom = 100\n' > "$USER_CONFIG/capacity.conf"
read_context | assert_json '.window_tokens == 100 and .capacity_source == "custom"'
cat > "$PROJECT_CONFIG/capacity.conf" <<'CAPACITY'
selected_model = sample
assistant_limit = small
model.sample = 1000
limit.small = 200
CAPACITY
read_context | assert_json '.window_tokens == 200 and .capacity_source == "assistant_limit"'
sed '/assistant_limit = small/d' "$PROJECT_CONFIG/capacity.conf" > "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == 1000 and .capacity_source == "model_preset"'
printf 'custom = 321\n' >> "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == 321 and .capacity_source == "custom"'
printf 'custom =\n' > "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == null and .used_percentage == null'
printf 'selected_model = missing\n' > "$TMP/explicit.conf"
if CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
[[ -s "$TMP/err" ]]
[[ -z "$("$BASH_BIN" -c 'source "$1/src/get-context.sh"' bash "$ROOT")" ]]
printf 'ok: capacity and configuration\n'

# Observable reminder sequences, isolated sessions, and concurrent delivery.
threshold_config() {
  jq -n --arg mode "$1" --arg dir "$TMP/state-$1" \
    '{thresholds:[{percent:50,level:"low",message:"low {percentage}"},{percent:80,level:"high",message:"high {remaining}"}],repeat_mode:$mode,flag_dir:$dir}' > "$PROJECT_CONFIG/config.json"
}
remind() {
  jq -cn --arg sid "$1" --argjson used "$2" --arg segment "$3" \
    '{session_id:$sid,used_percentage:$used,remaining_percentage:(if $used == null then null else 100-$used end),segment:$segment}' |
    "$BASH_BIN" "$ROOT/src/check-thresholds.sh" claude
}
threshold_config once_per_tier_reset_on_compaction
[[ "$(remind sequence 85 first)" == $'low 85\nhigh 15' ]]
[[ -z "$(remind sequence 85 first)" ]]
[[ -z "$(remind sequence 20 first)" ]]
[[ "$(remind sequence 55 first)" == 'low 55' ]]
[[ "$(remind sequence 55 second)" == 'low 55' ]]
[[ "$(remind other 55 first)" == 'low 55' ]]
[[ -z "$(remind unknown null first)" ]]
pids=()
for i in 1 2 3 4; do
  remind parallel 55 first > "$TMP/parallel-$i" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
[[ "$(cat "$TMP"/parallel-* | wc -l | tr -d ' ')" == 1 ]]
threshold_config once_per_tier
[[ "$(remind persistent 55 first)" == 'low 55' ]]
[[ -z "$(remind persistent 20 first)" ]]
[[ -z "$(remind persistent 55 second)" ]]
threshold_config every_turn
[[ "$(remind repeated 55 first)" == 'low 55' ]]
[[ "$(remind repeated 55 first)" == 'low 55' ]]
# Threshold configuration follows the same user/project/explicit precedence.
cp "$PROJECT_CONFIG/config.json" "$USER_CONFIG/config.json"
rm "$PROJECT_CONFIG/config.json"
[[ "$(remind scope 55 first)" == 'low 55' ]]
jq '.thresholds[0].message = "project"' "$USER_CONFIG/config.json" > "$PROJECT_CONFIG/config.json"
[[ "$(remind scope 55 first)" == project ]]
jq '.thresholds[0].message = "explicit"' "$USER_CONFIG/config.json" > "$TMP/thresholds.json"
[[ "$(CONTEXT_THRESHOLDS_CONFIG="$TMP/thresholds.json" remind scope 55 first)" == explicit ]]
printf 'ok: reminders and session state\n'

# Follow the README's standalone layout, for both scopes and paths with spaces.
for scope in "$CLAUDE_CONFIG_DIR" "$CLAUDE_PROJECT_DIR/.claude"; do
  runtime="$scope/context-awareness/runtime"
  skill="$scope/skills/get-my-context"
  mkdir -p "$runtime/claude" "$skill"
  cp -R "$ROOT/src" "$runtime/"
  cp "$ROOT/claude/read-context.sh" "$runtime/claude/"
  jq -Rrs --arg root "$runtime" 'split("${CLAUDE_PLUGIN_ROOT}") | join($root)' \
    "$ROOT/claude/skills/get-my-context/SKILL.md" > "$skill/SKILL.md"
  [[ "$(find "$skill" -type f | wc -l | tr -d ' ')" == 1 ]]
  command="$(sed -n 's/^!`\(.*\)`$/\1/p' "$skill/SKILL.md")"
  CLAUDE_SESSION_ID=reading "$BASH_BIN" -c "$command --json" | assert_json '.used_tokens == 0 and .window_tokens == 200'
done
export CLAUDE_PLUGIN_ROOT="$ROOT"
HOOK="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$ROOT/claude/hooks.json")"
request 10 20 30 > "$TRANSCRIPT"
printf 'custom = 100\n' > "$PROJECT_CONFIG/capacity.conf"
threshold_config every_turn
INPUT="$(jq -cn --arg cwd "$CLAUDE_PROJECT_DIR" --arg path "$TRANSCRIPT" '{session_id:"native-hook",cwd:$cwd,transcript_path:$path}')"
printf '%s\n' "$INPUT" | "$BASH_BIN" -c "$HOOK" |
  assert_json '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.additionalContext == "low 60"'
printf 'invalid\n' > "$PROJECT_CONFIG/capacity.conf"
code=0
printf '%s\n' "$INPUT" | "$BASH_BIN" -c "$HOOK" > "$TMP/out" 2> "$TMP/err" || code=$?
[[ "$code" == 1 && ! -s "$TMP/out" && -s "$TMP/err" ]]
[[ -z "$(find "$ROOT/src" "$ROOT/claude" -type l)" ]]
printf 'ok: standalone installation and registered hook\n'
