#!/usr/bin/env bash
# Latest Codex token_count in this session's current compaction segment.
set -euo pipefail
SID="$1"
TRANSCRIPT="${2:-}"
unavailable() {
  printf '%s\n' '{"used_tokens":null,"model":null,"measurement_source":"unavailable","measured_at":null,"segment":null,"measurement_basis":"codex_latest_total"}'
}
if [[ -z "$TRANSCRIPT" ]]; then
  paths=()
  while IFS= read -r path; do paths+=("$path"); done < <(
    find "${CODEX_HOME:-$HOME/.codex}/sessions" -maxdepth 4 -type f -name "rollout-*-$SID.jsonl" 2>/dev/null || true
  )
  # Never borrow another thread or arbitrarily pick between duplicate logs.
  if [[ ${#paths[@]} -ne 1 ]]; then unavailable; exit 0; fi
  TRANSCRIPT="${paths[0]}"
fi
if [[ ! -f "$TRANSCRIPT" ]]; then unavailable; exit 0; fi
if ! head -n 1 "$TRANSCRIPT" | jq -e --arg sid "$SID" \
  '.type == "session_meta" and .payload.id == $sid' >/dev/null 2>&1; then
  unavailable; exit 0
fi
# jq terminates at the current boundary; ignore only the producer's SIGPIPE.
(
  set +o pipefail
  if command -v tac >/dev/null 2>&1; then tac "$TRANSCRIPT"; else tail -r "$TRANSCRIPT"; fi |
    jq -Rn '
def count:
  if type == "number" and . >= 0 and floor == . then . else null end;
def reading:
  . as $record | .payload.info.last_token_usage as $usage |
  {used_tokens: ($usage.total_tokens | count),
   measurement_source:
     (if $usage.input_tokens == 0 and $usage.output_tokens == 0
         and ($usage.total_tokens | count) > 0
      then "native_estimate" else "request" end),
   measured_at: ($record.timestamp // null)};
first(foreach (inputs, null) as $line
  ({event: null, model: null, segment: "initial", done: false};
   if $line == null then .done = true else
     ($line | fromjson? // null) as $record |
     if ($record | type) != "object" then .
     elif $record.type == "compacted" then
       .segment = ($record.timestamp // ($record | tojson)) | .done = true
     elif $record.type == "event_msg" and $record.payload.type == "thread_rolled_back" then
       .segment = ("rollback:" + ($record.timestamp // ($record | tojson))) | .done = true
     elif .model == null and $record.type == "turn_context" then
       .model = ($record.payload.model // null)
     elif .event == null and $record.type == "event_msg"
       and $record.payload.type == "token_count" and $record.payload.info != null then
       .event = ($record | reading)
     else . end
   end;
   select(.done))) |
(.event // {used_tokens: null, measurement_source: "unavailable", measured_at: null})
+ {model: .model, segment: .segment, measurement_basis: "codex_latest_total"}
'
)
