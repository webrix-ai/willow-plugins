# Willow Plugins

A plugin marketplace for [Willow](https://webrix.ai) that works with Claude Code and Cursor. Install plugins on demand to add diagnostics and tooling for the `willow` CLI to your coding agent.

## Available plugins

| Plugin | Description |
| ------ | ----------- |
| [`willow-diagnose-plugin`](plugins/willow-diagnose-plugin) | Diagnose and fix `willow` CLI issues — "Daemon request timeout", auth failures, and gateway reachability. |

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
```

## License

MIT — see [LICENSE](LICENSE).
