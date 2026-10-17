---
name: get-my-context
description: Check context usage when asked or before starting a long task.
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/src/get-context.sh" claude *)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/src/get-context.sh" claude "${CLAUDE_SESSION_ID}" --project "${CLAUDE_PROJECT_DIR}"`

Use the reading to pace your work. Report usage only when the user asks.
If capacity differs from the context window or compaction limit stated for
this session, correct the reported capacity config and rerun.
