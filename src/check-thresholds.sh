#!/usr/bin/env bash
# Evaluate normalized readings and persist threshold repeat state.
set -euo pipefail
CONTEXT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CONTEXT_SRC/get-context.sh"
context_scope "${1:-}"
READING="$(cat)"
SID="$(jq -er '.session_id // empty' <<< "$READING")" || exit 0
context_session "$SID"
CONFIG="$(context_config config.json "${CONTEXT_THRESHOLDS_CONFIG:-}")"
jq -e '
  (.repeat_mode // "once_per_tier_reset_on_compaction") as $mode |
  (["once_per_tier", "once_per_tier_reset_on_compaction", "every_turn"] | index($mode)) != null
  and (.thresholds | type == "array")
  and all(.thresholds[]; (.percent | type == "number" and . >= 0 and . <= 100)
    and (.level | type == "string" and length > 0)
    and (.message | type == "string"))
  and ([.thresholds[].level] | length == (unique | length))
' "$CONFIG" >/dev/null || { context_error "invalid threshold config: $CONFIG"; exit 2; }
jq -e '.used_percentage != null' <<< "$READING" >/dev/null || exit 0
BASE="$(jq -er '.flag_dir // "/tmp" | select(type == "string" and length > 0)' "$CONFIG")"
STATE_DIR="$BASE/context-awareness-$(id -u)"
(umask 077; mkdir -p "$STATE_DIR")
STATE="$STATE_DIR/$SID.json"
LOCK="$STATE.lock"
# Parallel tool calls share one session's repeat state.
ATTEMPT=0
until mkdir "$LOCK" 2>/dev/null; do
  ATTEMPT=$(( ATTEMPT + 1 ))
  [[ "$ATTEMPT" -lt 50 ]] || exit 0
  sleep 0.02
done
TEMP=''
trap '[[ -z "$TEMP" ]] || rm -f "$TEMP"; rmdir "$LOCK"' EXIT
OLD='{}'
if [[ -f "$STATE" ]]; then OLD="$(cat "$STATE")"; fi
EVALUATED="$(jq -cn --argjson config "$(cat "$CONFIG")" --argjson reading "$READING" --argjson old "$OLD" '
  ($config.repeat_mode // "once_per_tier_reset_on_compaction") as $mode |
  (if $mode != "once_per_tier" and $old.segment != $reading.segment
   then {} else ($old.fired // {}) end) as $fired |
  reduce ($config.thresholds | sort_by(.percent))[] as $tier
    ({segment: $reading.segment, fired: $fired, messages: []};
     if $reading.used_percentage >= $tier.percent then
       if .fired[$tier.level] != true or $mode == "every_turn" then
         .messages += [$tier.message |
           split("{percentage}") | join($reading.used_percentage | tostring) |
           split("{remaining}") | join($reading.remaining_percentage | tostring) |
           split("{session_id}") | join($reading.session_id)] |
         .fired[$tier.level] = true
       else . end
     elif $mode != "once_per_tier" then del(.fired[$tier.level])
     else . end)')"
TEMP="$(mktemp "$STATE_DIR/.state-XXXXXX")"
jq 'del(.messages)' <<< "$EVALUATED" > "$TEMP"
mv -f "$TEMP" "$STATE"
TEMP=''
jq -r 'select(.messages | length > 0) | .messages | join("\n")' <<< "$EVALUATED"
