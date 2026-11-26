# Willow Diagnose Plugin

Triage common Willow problems directly from your coding agent. It is built for the usual setup, an AI client (Cursor, Claude Code, Claude Desktop, VS Code, Codex, ChatGPT, ...) connected to Willow as a regular **HTTP MCP server**, and it also covers the optional `willow` CLI. No CLI is needed for the main skills.

## Skills

| Skill | Use it when |
| ----- | ----------- |
| [`triage-willow`](skills/triage-willow) | Entry point. Something with Willow is broken and the cause is unknown. Classifies the symptom, probes the endpoint, collects redacted evidence, routes to the skills below, and writes the support report. |
| [`triage-willow-client-setup`](skills/triage-willow-client-setup) | The client doesn't see or reach Willow: Cursor ignores the entry (`"type": "http"`), Claude Code shows disconnected, wrong or `http://` URL, a URL that opens the web portal, per-client reconnect steps. |
| [`triage-willow-auth`](skills/triage-willow-auth) | `Unauthorized`/401 that doesn't resolve, Authorize never completes or opens, `localhost` 404, blocked popup, Re-authenticate not helping. |
| [`triage-willow-missing-tools`](skills/triage-willow-missing-tools) | Connected but no tools, a missing server or tool, a narrowed scope, a stale tool list, `Unknown account "<name>"`. |
| [`triage-willow-tool-failures`](skills/triage-willow-tool-failures) | A listed tool fails, is blocked, waits on approval, or returns schema/permission errors. |
| [`diagnose-willow`](skills/diagnose-willow) | **CLI only.** The `willow` CLI hangs, `Daemon request timeout`, `willow doctor` FAILs. |

## How the main skills think

An HTTP MCP connection is a short ladder, and every report maps to one rung. `triage-willow` finds the lowest rung that fails:

1. the client has a correct entry (an `https://` URL ending in the org's `/mcp`, the right `type`);
2. the client can reach it;
3. the gateway answers `401` with an OAuth challenge and the sign-in metadata is reachable (the `401` is **normal**);
4. the user completes Authorize in the browser and the client stores the token;
5. `tools/list` returns what this user may use, enabled and in scope;
6. `tools/call` reaches the user's own connection to that server, past any approvals and guards.

## Scripts

- `triage-willow/scripts/collect-evidence.sh` needs only `bash` and `curl` (Node.js and the CLI are used if present). It is strictly read-only. It lists the Willow entries in your client configs (type and URL only, never headers), probes each URL the way a client does before sign-in, checks the sign-in discovery endpoints, and redacts tokens, JWTs, emails and secret-looking values from everything it prints. The only traffic is unauthenticated requests to Willow URLs your clients already use, with query strings stripped.
- `diagnose-willow/scripts/diagnose.sh` is read-only by default. `--fix` (reset the daemon, then test with it off and restore the setting) and `--disable-daemon` are opt-in and meant to be run only after the user agrees.

## Usage

Ask your agent something like "I connected Willow but I see no tools", "I get 401 from Willow", "Cursor doesn't show my Willow MCP", or "willow keeps timing out" and it will pick the matching skill. You can also run the scripts directly:

```bash
bash skills/triage-willow/scripts/collect-evidence.sh > willow-evidence.txt
bash skills/diagnose-willow/scripts/diagnose.sh          # CLI only, read-only
bash skills/diagnose-willow/scripts/diagnose.sh --fix    # CLI only, after the user agrees
```

## Requirements

- For the main skills: `bash` and `curl`.
- Optional: the Willow MCP connected in the session. The `triage-willow-*` skills use it for read-only lookups of the user's server connections and recent calls, and find its tools by keyword in the client's tool list rather than by fixed name.
- Optional: the `willow` CLI on your `PATH` (override with `WILLOW_BIN`), for `diagnose-willow` and the CLI extras.

## Design notes

- Each skill folder is self-contained (no relative links to a sibling skill's files), so any one of them can be installed alone, including from the trusted skills catalog.
- Skills are read-only by default. Anything that changes the user's setup (editing a client config, reconnecting or disconnecting a server, signing out, stopping the daemon) is stated and needs the user's go-ahead.
- Known issues come from Willow's end-user docs (Troubleshooting, FAQ, Refresh Your Tools, MCP Servers, Willow CLI) and the gateway's observed behavior. When those change, update [`known-issues.md`](skills/triage-willow/references/known-issues.md) and the matching skill.
- The exact texts users see are catalogued per skill: browser sign-in error pages in [`sign-in-errors.md`](skills/triage-willow-auth/references/sign-in-errors.md), tool-call errors in [`error-messages.md`](skills/triage-willow-tool-failures/references/error-messages.md). Both are copied from the gateway and portal source, so update them when those messages change.
- Each skill folder is self-contained (no links into sibling folders), so it can be imported on its own into Willow's trusted skills catalog.

## Compatibility

- Claude / Claude Code
- Cursor
