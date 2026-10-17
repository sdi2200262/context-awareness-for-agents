#!/usr/bin/env bash
# Native paths and invocation; calculation and configuration policy live in src/.
context_adapter_scope() {
  CONTEXT_PROJECT_CONFIG="${CONTEXT_PROJECT_DIR:-$PWD}/.codex/context-awareness"
  CONTEXT_USER_CONFIG="${CODEX_HOME:-$HOME/.codex}/context-awareness"
}
context_adapter_session() { printf '%s\n' "${CODEX_THREAD_ID:-}"; }
context_adapter_read() { bash "$CONTEXT_INTEGRATION/read-context.sh" "$@"; }
