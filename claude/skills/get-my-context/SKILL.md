---
name: get-my-context
description: Check Claude Code context usage when asked how full the conversation is, how much room remains, or whether to compact. Also use before starting a long task.
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/src/get-context.sh" claude *)
---

# Context usage

!`bash "${CLAUDE_PLUGIN_ROOT}/src/get-context.sh" claude "${CLAUDE_SESSION_ID}"`

Report the latest recorded reading concisely. Explain its source or configuration
only when needed. It excludes generated output and does
not include messages added since that measurement. After compaction, it uses the
recorded post-compaction count until a newer request supplies usage. Unavailable
means unknown, not zero.

Context window capacity is explicitly configured, independently of the observed
model. If it needs changing, edit the configuration selected for this session:
`CONTEXT_CAPACITY_CONFIG` when set, otherwise the project's
`.claude/context-awareness/capacity.conf`, then the user-wide
`~/.claude/context-awareness/capacity.conf`. If `CLAUDE_CONFIG_DIR` is set, it
replaces `~/.claude` for the user-wide path. Project configuration overrides
user-wide configuration; either can be used regardless of plugin install scope.
Use `claude/capacity.conf` from this installation as a template when creating a
configuration. Use the user's chosen model preset, assistant limit, or custom value.
Do not infer capacity from your identity or plan, or edit the plugin cache.
