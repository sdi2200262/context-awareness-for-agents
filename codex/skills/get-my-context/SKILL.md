---
name: get-my-context
description: Read Codex context usage when asked how full the conversation is, how much room remains, or whether to compact. Also use before starting a long task.
---

Run the shared reader from this installation using the shell tool:

```bash
bash "<plugin-root>/src/get-context.sh" codex
```

Resolve `<plugin-root>` from this skill's location: three directories above
`codex/skills/get-my-context/`. Preserve spaces by quoting the absolute path.
The command uses `CODEX_THREAD_ID` to select this session and `CODEX_HOME`
(default `~/.codex`) to locate its records. Never select another session's log
or the most recently modified log. If the session ID is unavailable, report
that limitation rather than guessing.

Report the latest recorded reading concisely. Codex records a per-response
total including input and output; cached input is already included. After
compaction the recorded total can be Codex's own estimate until a new response.
It excludes additions since that measurement. Unavailable means unknown, not zero.

Capacity is explicitly configured; never infer it from model identity, plan,
or native window telemetry. Use `CONTEXT_CAPACITY_CONFIG` when set, otherwise
the project's `.codex/context-awareness/capacity.conf`, then
`${CODEX_HOME:-~/.codex}/context-awareness/capacity.conf`.
Start from this installation's `codex/capacity.conf` if needed. Keep overrides
outside the plugin cache. An unset capacity still permits a token reading.
