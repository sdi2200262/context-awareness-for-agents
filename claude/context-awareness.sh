#!/usr/bin/env bash
# Claude's registered hook entry point.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../src/context-awareness.sh" claude
