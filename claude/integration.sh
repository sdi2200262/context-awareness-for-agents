#!/usr/bin/env bash
# Native paths and invocation; calculation and configuration policy live in src/.
context_adapter_scope() {
  # Claude keeps this root stable when tools cd; hooks and skills share it.
  CONTEXT_PROJECT_CONFIG="${1:-${CLAUDE_PROJECT_DIR:-${CONTEXT_PROJECT_DIR:-$PWD}}}/.claude/context-awareness"
  CONTEXT_USER_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-awareness"
}
context_adapter_session() { printf '%s\n' "${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"; }
context_adapter_read() { bash "$CONTEXT_INTEGRATION/read-context.sh" "$@"; }
