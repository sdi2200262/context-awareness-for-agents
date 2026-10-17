#!/usr/bin/env bash
# Shared context command and configuration helpers.

context_error() { printf 'context-awareness: %s\n' "$*" >&2; return 2; }

context_session() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || context_error 'invalid or missing session ID'
}

context_config() {
  local name="$1" override="$2"
  if [[ -n "$override" ]]; then
    [[ -f "$override" ]] || { context_error "missing config: $override"; return 2; }
    printf '%s\n' "$override"
  elif [[ -f "$CONTEXT_PROJECT_CONFIG/$name" ]]; then
    printf '%s\n' "$CONTEXT_PROJECT_CONFIG/$name"
  elif [[ -f "$CONTEXT_USER_CONFIG/$name" ]]; then
    printf '%s\n' "$CONTEXT_USER_CONFIG/$name"
  elif [[ "$name" == config.json ]]; then
    printf '%s\n' "$CONTEXT_SRC/config.default.json"
  else
    printf '%s\n' "$CONTEXT_INTEGRATION/$name"
  fi
}

context_report() {
  local measurement="$1" sid="$2" format="$3" file capacity result
  file="$(context_config capacity.conf "${CONTEXT_CAPACITY_CONFIG:-}")" || return
  capacity="$(context_capacity "$file")" || return
  result="$(jq -cen --argjson measurement "$measurement" --argjson capacity "$capacity" --arg sid "$sid" --arg assistant "$CONTEXT_ASSISTANT" --arg config "$file" '
    if ($measurement | type) != "object"
      or ($measurement.used_tokens != null and
          ($measurement.used_tokens | type != "number" or . < 0 or floor != .))
      or ($measurement.measurement_source | type) != "string"
      or ($measurement.measurement_basis | type) != "string"
      or ($measurement.segment != null and ($measurement.segment | type) != "string")
    then error("invalid context measurement") else . end |
    $measurement + $capacity + {assistant: $assistant, session_id: $sid, capacity_config: $config} |
    .used_percentage = (if .used_tokens != null and .window_tokens != null
                       then (.used_tokens / .window_tokens * 100 | floor) else null end) |
    .remaining_percentage = (if .used_percentage != null then ([0, 100 - .used_percentage] | max) else null end) |
    .remaining_tokens = (if .used_tokens != null and .window_tokens != null
                         then ([0, .window_tokens - .used_tokens] | max) else null end)')" || return
  if [[ "$format" == json ]]; then
    printf '%s\n' "$result"
  else
    context_format_reading "$result"
  fi
}

# Shared by the skill command and every delivered hook reminder.
context_format_reading() {
  jq -r '
      if .used_tokens == null then "Context usage: unavailable for the current segment."
      elif .window_tokens == null then "Context usage: \(.used_tokens) tokens; capacity unconfigured."
      else "Context usage: \(.used_percentage)% used (\(.used_tokens) / \(.window_tokens) tokens), \(.remaining_percentage)% remaining (\(.remaining_tokens) tokens)."
      end + (if .measured_at != null then " Recorded at \(.measured_at)." else "" end),
      "Assistant: \(.assistant). Capacity model preset: \(.configured_model // "none") (\(.capacity_source)); assistant limit: \(.assistant_limit // "none"). Recorded model: \(.model // "unknown").",
      "Capacity config: \(.capacity_config)"' <<< "$1"
}

context_capacity() {
  jq -Rn '
def trim: gsub("^\\s+|\\s+$"; "");
def positive:
  test("^[0-9]+$") and (tonumber > 0 and tonumber <= 1000000000);
reduce inputs as $line ({};
  ($line | sub("#.*$"; "") | trim) as $text |
  if $text == "" then . else
    ($text | split("=") | map(trim)) as $pair |
    if ($pair | length) != 2 then error("expected key = value") else
      $pair[0] as $key | $pair[1] as $value |
      if has($key) then error("duplicate capacity setting: " + $key)
      elif ($key | test("^(selected_model|assistant_limit|custom|model\\.[A-Za-z0-9_.-]+|limit\\.[A-Za-z0-9_.-]+)$") | not)
        then error("unknown capacity setting: " + $key)
      elif ($key == "selected_model" or $key == "assistant_limit") then
        if ($value | test("^[A-Za-z0-9_.-]*$")) then .[$key] = $value
        else error("invalid preset name: " + $key) end
      elif $key == "custom" and $value == "" then .[$key] = $value
      elif ($value | positive) then .[$key] = $value
      else error("capacity must be a positive integer: " + $key) end
    end
  end
) |
def preset($selection; $prefix):
  (.[$selection] // "") as $name |
  if $name == "" then null
  elif has($prefix + $name) then .[$prefix + $name] | tonumber
  else error("undefined preset: " + $name) end;
if (.custom // "") != "" then
  {window_tokens: (.custom | tonumber), capacity_source: "custom"}
else
  preset("selected_model"; "model.") as $model |
  preset("assistant_limit"; "limit.") as $limit |
  {window_tokens: ([$model, $limit] | map(select(. != null)) | if length > 0 then min else null end),
   capacity_source: (if $limit != null and ($model == null or $limit < $model) then "assistant_limit"
                     elif $model != null then "model_preset" else "unconfigured" end)}
end + {
  configured_model: (if (.selected_model // "") == "" then null else .selected_model end),
  model_window_tokens: ((.["model." + (.selected_model // "")] // null) | if . == null then null else tonumber end),
  assistant_limit: (if (.assistant_limit // "") == "" then null else .assistant_limit end),
  assistant_limit_tokens: ((.["limit." + (.assistant_limit // "")] // null) | if . == null then null else tonumber end)
}
' "$1"
}

context_scope() {
  CONTEXT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]] || { context_error "invalid assistant: $1"; return 2; }
  CONTEXT_ASSISTANT="$1"
  CONTEXT_INTEGRATION="$CONTEXT_SRC/../$CONTEXT_ASSISTANT"
  [[ -f "$CONTEXT_INTEGRATION/integration.sh" ]] || {
    context_error "unsupported assistant: $1"; return 2;
  }
  source "$CONTEXT_INTEGRATION/integration.sh"
  context_adapter_scope "${2:-}"
}

context_main() {
  set -euo pipefail
  local assistant="${1:-}" sid='' format=text transcript='' project='' measurement
  [[ $# -ge 1 ]] || { context_error 'usage: get-context.sh ASSISTANT [SESSION_ID] [--json] [--transcript PATH] [--project DIR]'; return 2; }
  shift
  if [[ $# -gt 0 && "$1" != --* ]]; then sid="$1"; shift; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) format=json; shift ;;
      --transcript)
        [[ $# -gt 1 ]] || { context_error '--transcript needs a path'; return 2; }
        transcript="$2"; shift 2 ;;
      --project)
        [[ $# -gt 1 && -d "$2" ]] || { context_error '--project needs an existing directory'; return 2; }
        project="$(cd "$2" && pwd)"; shift 2 ;;
      *) context_error "unknown argument: $1"; return 2 ;;
    esac
  done
  context_scope "$assistant" "$project"
  if [[ -z "$sid" ]]; then sid="$(context_adapter_session)"; fi
  context_session "$sid"
  measurement="$(context_adapter_read "$sid" "$transcript")"
  context_report "$measurement" "$sid" "$format"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  context_main "$@"
fi
