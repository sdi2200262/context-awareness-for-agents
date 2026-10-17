---
name: get-my-context
description: Check context usage when asked or before starting a long task.
---

Run this installation's reader with the shell tool:

```bash
bash "<plugin-root>/src/get-context.sh" codex
```

`<plugin-root>` is three directories above this skill's directory,
`codex/skills/get-my-context/`. Quote the absolute path. The reader uses
`CODEX_THREAD_ID` to select the current session.

Use the reading to pace your work. Report usage only when the user asks.
If capacity differs from the context window or compaction limit stated for
this session, correct the reported capacity config and rerun.
