# Willow Plugins

A plugin marketplace for [Willow](https://webrix.ai) that works with Claude Code and Cursor. Install plugins on demand to add diagnostics and tooling for the `willow` CLI to your coding agent.

## Available plugins

| Plugin | Description |
| ------ | ----------- |
| [`willow-diagnose-plugin`](plugins/willow-diagnose-plugin) | Diagnose and triage Willow problems — `willow` CLI issues ("Daemon request timeout", auth, gateway reachability) and known end-user issues (no tools, 401, client setup, failing tool calls). |

## Install

### Claude Code

```bash
/plugin marketplace add webrix-ai/willow-plugins
/plugin install willow-diagnose-plugin
```

### Cursor

Add the marketplace from this repository, then install `willow-diagnose-plugin` from the plugins list.

## Repository layout

```text
willow-plugins/
  .cursor-plugin/
    marketplace.json            # marketplace manifest
  plugins/
    willow-diagnose-plugin/
      .claude-plugin/plugin.json
      .cursor-plugin/plugin.json
      README.md
      skills/
        diagnose-willow/
          SKILL.md
          scripts/diagnose.sh
        triage-willow/
          SKILL.md
          references/known-issues.md
          scripts/collect-evidence.sh
        triage-willow-missing-tools/SKILL.md
        triage-willow-auth/SKILL.md
        triage-willow-client-setup/SKILL.md
        triage-willow-tool-failures/SKILL.md
```

## License

MIT — see [LICENSE](LICENSE).
