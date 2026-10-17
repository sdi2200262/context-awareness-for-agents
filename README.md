# Context awareness for agents

Check how much context your agent has accumulated, and give it instructions at
chosen thresholds. Supports Claude Code and Codex. Requires Bash 3.2+ and
[jq](https://jqlang.github.io/jq/download/).

<p align="center">
  <img src="assets/diagram.svg" alt="Context-based instructions steering the agent's workflow" width="800"/>
</p>

## Install

Follow these instructions, or ask your agent to follow them.

<details>
<summary><strong>Claude Code</strong></summary>

Run in Claude Code and choose user-wide or project scope when installing:

```text
/plugin marketplace add sdi2200262/context-awareness-for-agents
/plugin install context-awareness@context-awareness-for-agents
```

Restart Claude and invoke `/context-awareness:get-my-context`.

For on-demand readings using the skill only, disable this plugin's hooks.

</details>

<details>
<summary><strong>Codex</strong></summary>

Run in a terminal:

```sh
codex plugin marketplace add sdi2200262/context-awareness-for-agents
codex plugin add context-awareness@context-awareness-for-agents
```

Restart Codex and select `get-my-context` from its skills picker, or ask it to
use that skill. Review and trust the plugin's hooks through `/hooks` to enable
threshold reminders. For on-demand readings only, leave the hooks disabled.

The skill runs a shell command under Codex's normal permissions. Local Codex
session records are required; Claude's automatic skill preprocessing is not
available in Codex.

</details>

## Configure

Claude defaults to **1,000,000-token capacity** (Opus 5.5 preset). Codex starts
with capacity unset: choose a capacity to enable percentages and reminders.
Both use a **70% reminder threshold**.

To customize, create or edit these files, or ask your agent to do it.
Use the appropriate directory for all projects or one project:

| Assistant | User settings | Project settings | Capacity template |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/context-awareness/` | `.claude/context-awareness/` | [capacity.conf](claude/capacity.conf) |
| Codex | `~/.codex/context-awareness/` | `.codex/context-awareness/` | [capacity.conf](codex/capacity.conf) |

Create `capacity.conf` from its template to choose a model preset, assistant
limit, or custom capacity. Create [config.json](src/config.default.json) to
choose reminder thresholds, messages, and repeat behavior.

Project settings override user settings. `CLAUDE_CONFIG_DIR` and `CODEX_HOME`
replace the respective user roots. `CONTEXT_CAPACITY_CONFIG` and
`CONTEXT_THRESHOLDS_CONFIG` select explicit files ahead of either scope; if
exported to both assistants, both use those files. Keep overrides outside the
installed plugin so updates preserve them. Assistants keep separate session state.

Readings reflect the latest recorded usage; new messages may not yet be counted.
Claude counts request input and cache tokens; Codex uses its latest recorded
total including output, or its native estimate following compaction.

## License

[MIT](LICENSE).

<p align="center">
  <a href="https://github.com/sdi2200262" target="_blank">
    <img src="assets/cobuter-man.png" alt="CobuterMan" width="150"/>
  </a>
</p>
