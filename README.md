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

For on-demand readings only, use the skill-only configuration below.

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
threshold reminders. For on-demand readings only, use the skill-only configuration
below.

The skill runs a shell command under Codex's normal permissions. Local Codex
session records are required; Claude's automatic skill preprocessing is not
available in Codex.

</details>

## Configure

Claude defaults to **1,000,000-token capacity** (Opus 5.5 preset). Codex defaults
to **475,000-token capacity** (GPT-6.1 Sol preset capped for a 500k Codex window).
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

The Codex template separates **API model maxima** from **configured Codex
windows**. Its GPT-6.1 Sol, GPT-6 Astra, GPT-6 Sol and GPT-6 Luna API presets are
1,050,000 tokens ([OpenAI model specifications](https://developers.openai.com/api/docs/models)).
The `codex-500k` and `codex-272k` assistant limits use 475,000 and 258,400 tokens,
respectively, after [Codex's 5% reserve](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/openai_models.rs).
These are observed configurations, not plan guarantees. Choose the limit that
matches your setup; Codex can compact before that window fills.

To use an API maximum as the denominator, clear `assistant_limit` in your copied
template. API authentication alone does not enlarge Codex's configured window.
These settings only control this plugin's percentages and reminders; they do
not configure Codex or detect its model, window, authentication method or plan.
For another usable capacity, add a limit preset or set `custom`.

Project settings override user settings. `CLAUDE_CONFIG_DIR` and `CODEX_HOME`
replace the respective user roots. `CONTEXT_CAPACITY_CONFIG` and
`CONTEXT_THRESHOLDS_CONFIG` select explicit files ahead of either scope; if
exported to both assistants, both use those files. Keep overrides outside the
installed plugin so updates preserve them. Assistants keep separate session state.

For **skill-only mode**, set `"hooks": false` in the assistant's user or project
`config.json`. A new file can contain just:

```json
{"hooks": false}
```

The skill stays available. Automatic monitoring exits before reading session data
or touching reminder state. The host still starts the small hook process.
An empty `"thresholds": []` also skips monitoring. Omitting `hooks` means enabled.

For example, keep both enabled globally and use the file above in one project's
settings directory to make that project skill-only. For the reverse, set
`hooks` to `false` in user settings and copy the [default config](src/config.default.json)
into a project's settings directory to enable its reminders. Configuration files
replace lower-priority files; they are not merged. No project plugin reinstall
is needed. Changes apply on the next tool call.

Keep the plugin enabled; the assistant's native hook permissions and trust still
apply when reminders are enabled.

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
