# Adding an assistant

Keep integrations beside `src/`:

| File | Responsibility |
| --- | --- |
| `integration.sh` | Define `context_adapter_scope [PROJECT_DIR]` (project/user config paths), `context_adapter_session` (native session ID), and `context_adapter_read SESSION_ID PATH_HINT` (normalized measurement). |
| `read-context.sh` | Parse native usage for the exact session. Resolve it by session ID when the optional path hint is empty. |
| `capacity.conf` | Explicit defaults and presets, independent of telemetry. |
| Native registration | Skills, hooks and plugin metadata supported by the host. |

The reader returns `used_tokens` (nonnegative integer or null), `model`,
`measurement_source`, `measurement_basis`, `measured_at`, and `segment`.
Use null for unknown readings and stable string identifiers for compaction
segments. Return null after a boundary until a new count is available. Document
cache, output and estimate accounting.

Reuse the shared engine:

| Module | Responsibility |
| --- | --- |
| `src/get-context.sh` | Config precedence, capacity validation, percentages and reporting. |
| `src/check-thresholds.sh` | Reminder evaluation and locks, isolated by assistant and session. |
| `src/context-awareness.sh` | Claude/Codex `PreToolUse` / `additionalContext` transport. Add a transport for other protocols. |

Use `context_format_reading` for the skill's text output and hook summaries.
Every delivered reminder includes usage, assistant, configured and recorded
models, capacity config path, and guidance to correct a confirmed mismatch.

Skills and hooks must identify their assistant and share its reader. Keep native
paths, accounting and invocation in the integration; hook and skill preprocessing
support are optional.

Use the same project scope for skills and hooks. Claude uses the stable
`CLAUDE_PROJECT_DIR` root; the skill passes its substituted value with `--project`
because the shell may lack that environment variable. Codex searches upward from
the working directory to the Git root for settings. Adapters must honor an
explicit `PROJECT_DIR` argument before their native defaults.

Configuration selects whole files in this order: explicit, project, user, default.
Hook transports must call `context_threshold_config` and `context_hooks_enabled`
before reading usage or capacity. `hooks: false` or empty thresholds skip
monitoring, preserving state and skill access. Pass the same validated snapshot
to `context_check_thresholds` after measuring.

Run `bash test/test.sh`. Add native fixtures to `test/readers.sh`, integration
coverage to `test/integrations.sh`, and mode coverage to `test/modes.sh`.
Verify separate settings and state for assistants sharing a project/session ID;
reuse shared calculation and reminder tests.

Before claiming support, install in a temporary project and test native skill
invocation, permissions, independently checked usage, reminders, compaction and
resumption.
