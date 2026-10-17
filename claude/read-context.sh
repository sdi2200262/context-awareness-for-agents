#!/usr/bin/env bash
# Latest recorded Claude input-side usage within the current compaction segment.
set -euo pipefail
SID="$1"
TRANSCRIPT="${2:-}"
if [[ -z "$TRANSCRIPT" ]]; then
  TRANSCRIPT="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -maxdepth 2 -type f -name "$SID.jsonl" 2>/dev/null | head -1 || true)"
fi
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" || ! -r "$TRANSCRIPT" ]]; then
  printf '%s\n' '{"used_tokens":null,"model":null,"measurement_source":"unavailable","measured_at":null,"segment":null,"measurement_basis":"input_and_cache"}'
  exit 0
fi
# jq stops at the first boundary; only the reverse reader's SIGPIPE is harmless.
(
  set +o pipefail
  # Early termination is expected; GNU tac can diagnose its harmless broken pipe.
  if command -v tac >/dev/null 2>&1; then tac "$TRANSCRIPT" 2>/dev/null; else tail -r "$TRANSCRIPT" 2>/dev/null; fi |
    jq -Rn '
# Read reversed JSONL until the current segment boundary or the start of file.
def count:
  if type == "number" and . >= 0 and floor == . then . else null end;
def request:
  . as $record |
  [.message.usage.input_tokens,
   (.message.usage.cache_creation_input_tokens // 0),
   (.message.usage.cache_read_input_tokens // 0)] | map(count) |
  {used_tokens: (if any(. == null) then null else add end),
   model: ($record.message.model // null), measurement_source: "request",
   measured_at: ($record.timestamp // null)};
first(foreach (inputs, null) as $line
  ({event: null, segment: "initial", done: false};
   if $line == null then .done = true
   # Native boundary names are literal ASCII. After finding the reading,
   # decode only boundary candidates while locating the current segment.
   elif .event != null and ($line | contains("compact_boundary") | not) then .
   else
     ($line | fromjson? // null) as $record |
     if ($record | type) != "object" or $record.isSidechain == true
       or ($record.type == "assistant" and $record.message.model == "<synthetic>") then .
     elif $record.type == "system" and $record.subtype == "compact_boundary" then
       .segment = ($record.uuid // $record.timestamp // ($record | tojson)) |
       .done = true |
       .event //= {used_tokens: ($record.compactMetadata.postTokens | count),
                   model: null, measurement_source: "compaction",
                   measured_at: ($record.timestamp // null)}
     elif .event == null and $record.type == "assistant"
       and $record.message.usage.input_tokens != null then
       .event = ($record | request)
     else . end
   end;
   select(.done))) |
(.event // {used_tokens: null, model: null, measurement_source: "unavailable", measured_at: null})
+ {segment: .segment, measurement_basis: "input_and_cache"}
'
)
