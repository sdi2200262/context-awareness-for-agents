# Adding an assistant

Keep assistant directories beside `src/`. Each integration contains:

- `integration.sh`: define `context_adapter_scope` (project/user configuration
  directories), `context_adapter_session` (current native session ID), and
  `context_adapter_read SESSION_ID PATH_HINT` (one normalized JSON measurement).
- `read-context.sh`: parse that assistant's recorded usage. Locate the exact
  session when the optional path hint is empty; never pick the newest session.
- `capacity.conf`: explicit default selections and relevant presets.
- Native skill, hook registration and plugin metadata as supported by the host.

The reader returns `used_tokens` (nonnegative integer or null), `model`,
`measurement_source`, `measurement_basis`, `measured_at`, and `segment`.
Use null for unknown readings. Give each compaction segment a stable string
identifier. Do not revive readings across a boundary when no new count exists.
Document whether a native count includes cached input, output or estimates.
Capacity selection is separate from telemetry.

`src/get-context.sh` owns configuration precedence, capacity validation,
percentages and reporting. `src/check-thresholds.sh` owns reminder behavior and
locks, isolated by assistant and session. `src/context-awareness.sh` provides
the JSON `PreToolUse`/`additionalContext` transport used by Claude and Codex;
an assistant with a different hook protocol should add only its own transport.
The skill and hooks must identify their assistant explicitly and use the same
reader. Native paths, accounting and invocation capabilities belong to the
integration. A reader does not require hook or skill-preprocessing support.

All hook transports must resolve and validate reminder configuration before
reading native usage or capacity. Use `context_threshold_config` and
`context_hooks_enabled` from `src/check-thresholds.sh`: `hooks: false` or an empty
threshold list skips monitoring while the skill remains available. Pass the same
validated JSON snapshot to `context_check_thresholds`; do not reload configuration
after measuring. Existing reminder state is preserved while monitoring is off.
Configuration uses explicit > project > user > default whole-file selection.

Run `bash test/test.sh`. Shared calculations and reminder sequences run once,
using normalized readings. Add native fixtures to `test/readers.sh` and extend
`test/integrations.sh` for configuration, package discovery and transports.
Test two assistants in the same project with different settings, and the same
session ID across assistants, to catch accidental coupling.

Before claiming support, also install the package in a temporary project and
test through the assistant's native interface: skill invocation, permissions,
independently checked usage, reminder delivery, compaction and resumption.
Fixtures and package-path checks do not establish native runtime behavior.
