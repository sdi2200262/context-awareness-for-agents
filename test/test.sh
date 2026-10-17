#!/usr/bin/env bash
# Shared behavior runs once; each integration supplies its native contract checks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for suite in readers shared integrations modes; do
  "${BASH_BIN:-bash}" "$ROOT/test/$suite.sh"
done
