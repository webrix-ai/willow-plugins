# Willow Diagnose Plugin

Diagnose and fix common `willow` CLI problems — "Daemon request timeout", expired auth, and gateway reachability — directly from your coding agent.

## What It Does

Adds the `diagnose-willow` skill, which teaches the agent how to triage `willow`
failures and ships a safe, re-runnable `diagnose.sh` that:

1. Runs `willow doctor` (built-in env / config / auth / daemon / MCP checks).
2. Clears a stale daemon (kills the pid and removes `/tmp/willow-$(id -u)/`).
3. Confirms auth with `willow auth status` (and prompts `willow auth login`).
4. Retries `willow tools grep test` with and without the daemon.
5. Prints gateway reachability guidance for a support ticket.

## Usage

Ask your agent something like "willow keeps timing out" or "fix willow daemon
request timeout" and it will activate this skill. You can also run the script
directly:

```bash
bash skills/diagnose-willow/scripts/diagnose.sh
```

## Requirements

- The `willow` CLI on your `PATH` (override with `WILLOW_BIN`).

## Compatibility

- Claude / Claude Code
- Cursor
