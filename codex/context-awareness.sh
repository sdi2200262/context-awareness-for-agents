#!/usr/bin/env bash
# Codex's registered hook entry point.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../src/context-awareness.sh" codex
