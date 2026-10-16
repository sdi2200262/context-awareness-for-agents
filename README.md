# Context awareness for agents

Check how much context your agent has accumulated, and give it instructions at
chosen thresholds. Supports Claude Code. Requires Bash 3.2+ and
[jq](https://jqlang.github.io/jq/download/).

<p align="center">
  <img src="assets/diagram.svg" alt="Context-based instructions steering the agent's workflow" width="800"/>
</p>

Check recorded usage on demand, or give the agent instructions at chosen thresholds.

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

## Configure

The plugin works with defaults: **1,000,000-token capacity** (Opus 5.5 preset)
and a **70% reminder threshold**.

To customize, create or edit these files, or ask your agent to do it.
Use `~/.claude/context-awareness/` for all projects or
`<project>/.claude/context-awareness/` for one project. Start from the linked
templates if the files do not exist:

- [capacity.conf](src/capacity.conf): choose a model preset, assistant limit, or custom capacity.
- [config.json](src/config.default.json): choose reminder thresholds, messages, and repeat behavior.

Project settings override user settings. `CLAUDE_CONFIG_DIR`, when set, replaces
`~/.claude`. Keep overrides outside the installed plugin so updates preserve them.

Readings reflect the latest recorded usage; new messages may not yet be counted.

## License

[MIT](LICENSE).

<p align="center">
  <a href="https://github.com/sdi2200262" target="_blank">
    <img src="assets/cobuter-man.png" alt="CobuterMan" width="150"/>
  </a>
</p>
