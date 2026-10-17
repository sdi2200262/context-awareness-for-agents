#!/usr/bin/env bash
# Native paths and invocation; calculation and configuration policy live in src/.
context_adapter_scope() {
  local project="${1:-${CONTEXT_PROJECT_DIR:-$PWD}}" parent
  # Look up to the nearest Git root, including a worktree's .git file.
  # A closer settings directory or an explicit --project takes precedence.
  if [[ -z "${1:-}" ]]; then
    parent="$(cd "$project" && pwd)" || return
    while [[ "$parent" != / ]]; do
      if [[ -d "$parent/.codex/context-awareness" || -e "$parent/.git" ]]; then project="$parent"; break; fi
      parent="${parent%/*}"
      [[ -n "$parent" ]] || parent=/
    done
  fi
  CONTEXT_PROJECT_CONFIG="$project/.codex/context-awareness"
  CONTEXT_USER_CONFIG="${CODEX_HOME:-$HOME/.codex}/context-awareness"
}
context_adapter_session() { printf '%s\n' "${CODEX_THREAD_ID:-}"; }
context_adapter_read() { bash "$CONTEXT_INTEGRATION/read-context.sh" "$@"; }
