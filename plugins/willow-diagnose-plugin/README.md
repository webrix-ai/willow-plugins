# Willow Diagnose Plugin

Diagnose and fix common Willow problems directly from your coding agent: the `willow` CLI ("Daemon request timeout", expired auth, gateway reachability) and the known end-user issues (no tools, 401, client setup, failing tool calls).

## Skills

| Skill | Use it when |
| ----- | ----------- |
| [`diagnose-willow`](skills/diagnose-willow) | The `willow` CLI hangs, `Daemon request timeout`, `willow doctor` FAILs. |
| [`triage-willow`](skills/triage-willow) | Entry point. Something with Willow is broken and the cause is unknown. Classifies the symptom, collects redacted evidence, routes to the skills below, and writes the support report. |
| [`triage-willow-missing-tools`](skills/triage-willow-missing-tools) | Connected but no tools, a missing server or tool, a stale tool list, `Unknown account "<name>"`. |
| [`triage-willow-auth`](skills/triage-willow-auth) | `Unauthorized`/401, Authorize never completes, `localhost` 404, blocked popup, `willow auth` exit code 4, Re-authenticate not helping. |
| [`triage-willow-client-setup`](skills/triage-willow-client-setup) | Cursor ignores the entry (`"type": "http"`), Claude Code disconnected, wrong URL, per-client reconnect steps. |
| [`triage-willow-tool-failures`](skills/triage-willow-tool-failures) | A listed tool fails, is blocked, waits on approval, or returns schema/permission errors. |

`diagnose-willow` ships a re-runnable `diagnose.sh`. `triage-willow` ships `collect-evidence.sh`, which is strictly read-only: it changes nothing, and redacts tokens, JWTs, emails and secret-looking values from everything it prints.

## Usage

Ask your agent something like "willow keeps timing out", "I connected Willow but I see no tools", or "I get 401 from Willow" and it will pick the matching skill. You can also run the scripts directly:

```bash
bash skills/diagnose-willow/scripts/diagnose.sh
bash skills/triage-willow/scripts/collect-evidence.sh > willow-evidence.txt
```

## Requirements

- The `willow` CLI on your `PATH` (override with `WILLOW_BIN`) for the CLI checks.
- Optional: the Willow MCP connected in the session. The `triage-willow-*` skills use it for read-only lookups of the user's server connections and recent calls, and find its tools by keyword (`willow tools grep`) rather than by fixed name.

## Design notes

- Each skill folder is self-contained (no relative links to a sibling skill's files), so any one of them can be installed alone, including from the trusted skills catalog.
- Skills are read-only by default. Anything that changes the user's setup (editing a client config, logout, disconnect, disabling the daemon) is stated and needs the user's go-ahead.
- Known issues come from Willow's end-user docs (Troubleshooting, FAQ, Refresh Your Tools, MCP Servers, Willow CLI). When those change, update [`known-issues.md`](skills/triage-willow/references/known-issues.md) and the matching skill.

## Compatibility

- Claude / Claude Code
- Cursor
