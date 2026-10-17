#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
# Shared calculations use a normalized reading, independent of native formats.
source "$ROOT/src/get-context.sh"
context_scope claude
read_context() { context_report '{"used_tokens":0,"measurement_source":"fixture","measurement_basis":"fixture","model":null,"measured_at":null,"segment":"initial"}' reading json; }
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
read_context | assert_json '.window_tokens == 200 and .capacity_source == "assistant_limit" and .configured_model == "sample" and .model_window_tokens == 1000 and .assistant_limit == "small" and .assistant_limit_tokens == 200 and .remaining_tokens == 200'
read_context | jq -e --arg config "$PROJECT_CONFIG/capacity.conf" '.capacity_config == $config' >/dev/null
sed '/assistant_limit = small/d' "$PROJECT_CONFIG/capacity.conf" > "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == 1000 and .capacity_source == "model_preset"'
printf 'custom = 321\n' >> "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == 321 and .capacity_source == "custom" and .configured_model == "sample" and .model_window_tokens == 1000 and .assistant_limit == null and .assistant_limit_tokens == null'
printf 'custom =\n' > "$TMP/explicit.conf"
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context | assert_json '.window_tokens == null and .used_percentage == null and .remaining_tokens == null and .configured_model == null and .model_window_tokens == null'
printf 'selected_model = missing\n' > "$TMP/explicit.conf"
if CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" read_context > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
[[ -s "$TMP/err" ]]
[[ -z "$("$BASH_BIN" -c 'source "$1/src/get-context.sh"' bash "$ROOT")" ]]
printf 'ok: capacity and configuration\n'

# Reports distinguish the configured preset from the recorded model, and expose
# the actual selected file so the skill can correct the denominator if needed.
measurement='{"used_tokens":60,"measurement_source":"fixture","measurement_basis":"fixture","model":"recorded-other","measured_at":null,"segment":"initial"}'
context_report "$measurement" reading json |
  assert_json '.model == "recorded-other" and .configured_model == "sample" and .used_tokens == 60 and .used_percentage == 30 and .remaining_tokens == 140 and .model_window_tokens == 1000'
report="$(context_report "$measurement" reading text)"
[[ "$report" == *'30% used (60 / 200 tokens)'* && "$report" == *'70% remaining (140 tokens)'* ]]
[[ "$report" == *'Recorded model: recorded-other'* && "$report" == *'Capacity model preset: sample'* ]]
[[ "$report" == *"Capacity config: $PROJECT_CONFIG/capacity.conf"* ]]
# Restored or resumed readings show when they were recorded.
context_report "$(jq -c '.measured_at = "2026-10-17T12:00:00Z"' <<< "$measurement")" reading text |
  grep -qF 'tokens). Recorded at 2026-10-17T12:00:00Z.'
context_report '{"used_tokens":250,"measurement_source":"fixture","measurement_basis":"fixture"}' reading json |
  assert_json '.used_percentage == 125 and .remaining_tokens == 0 and .remaining_percentage == 0'
context_report '{"used_tokens":null,"measurement_source":"unavailable","measurement_basis":"fixture"}' reading json |
  assert_json '.used_percentage == null and .remaining_tokens == null and .configured_model == "sample"'
CONTEXT_CAPACITY_CONFIG="$TMP/explicit.conf" context_report "$measurement" reading json 2>/dev/null && exit 1
printf 'ok: capacity provenance, token counts and model reporting\n'

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

# A stale lock is recovered; a fresh one makes the hook skip quietly.
threshold_config once_per_tier
lock_base="$TMP/state-once_per_tier/context-awareness-$(id -u)/claude"
mkdir -p "$lock_base/stale.json.lock" "$lock_base/live.json.lock"
touch -t 200001010000 "$lock_base/stale.json.lock"
[[ "$(remind stale 55 first)" == 'low 55' && ! -e "$lock_base/stale.json.lock" ]]
touch -t 200001010000 "$lock_base/file.json.lock"
[[ "$(remind file 55 first)" == 'low 55' && ! -e "$lock_base/file.json.lock" ]]
[[ -z "$(remind live 55 first)" && -d "$lock_base/live.json.lock" ]]
rmdir "$lock_base/live.json.lock"
# A state root planted as a symlink is rejected without writing to its target.
mkdir "$TMP/unsafe-base" "$TMP/unsafe-target"
ln -s "$TMP/unsafe-target" "$TMP/unsafe-base/context-awareness-$(id -u)"
jq --arg dir "$TMP/unsafe-base" '.flag_dir = $dir' "$PROJECT_CONFIG/config.json" > "$TMP/unsafe.json"
if CONTEXT_THRESHOLDS_CONFIG="$TMP/unsafe.json" remind unsafe 55 first > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
[[ -z "$(ls -A "$TMP/unsafe-target")" && -s "$TMP/err" ]]
printf 'ok: stale lock recovery and owned state paths\n'


# Numeric/configuration edge cases are independent of assistant telemetry.
for content in 'custom = 0' 'custom = -1' 'custom = 1.5' 'custom = nope' 'custom = 1000000001' 'custom = 1
custom = 2' 'unexpected = 10' 'selected_model = missing' 'custom'; do
  printf '%s\n' "$content" > "$TMP/invalid.conf"
  if context_capacity "$TMP/invalid.conf" > "$TMP/out" 2> "$TMP/err"; then
    printf 'FAIL: invalid capacity accepted\n' >&2; exit 1
  fi
done
printf 'assistant_limit = small\nlimit.small = 200\n' > "$TMP/limit.conf"
context_capacity "$TMP/limit.conf" | assert_json '.window_tokens == 200'
if context_report '{"used_tokens":-1,"measurement_source":"fixture","measurement_basis":"fixture"}' reading json > "$TMP/out" 2> "$TMP/err"; then exit 1; fi
printf 'ok: shared validation\n'
