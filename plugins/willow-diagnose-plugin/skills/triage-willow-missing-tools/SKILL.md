---
name: triage-willow-missing-tools
description: >-
  Fix Willow connections that work but show no tools, or the wrong ones: AI
  client says "no tools available", an MCP server or tool is missing, tool names
  or API-key `account` choices look out of date, `Unknown account "<name>"`,
  empty `willow tools list`, or only one server's tools appear. Use when the
  user is connected and signed in but the tool list is empty, partial or stale.
---

# Triage: no tools, missing tools, or a stale tool list

The connection exists, but the tools the user expects aren't there. Work down
the checks in order and stop at the first one that explains it. All checks are
read-only until the **Fix** at the end of a step.

## Step 1 — Is it really signed in?

An unauthenticated connection looks exactly like "no tools". If the user
closed the browser Authorize page without clicking **Authorize**, the
connection was never authenticated.

- CLI: `willow auth status` (exit 4 = not signed in).
- Otherwise: use the `triage-willow-auth` skill first, then come back.

## Step 2 — Is the client asking for a narrowed scope?

A URL ending in `?mcp=<server>` or `?toolkit=<name>`, or in the path form
`/mcp/mcp/<server>` or `/mcp/toolkit/<name>`, deliberately shows only that
server or toolkit. A **Use** button on a server card builds exactly such a URL.
The CLI has the same thing in contexts.

```bash
willow context list        # starred = active; shows its --mcp / --toolkit
willow config show         # look for mcp / toolkit scoping (no secrets printed)
```

Fix: use the unscoped URL from **Connect MCP**, or `willow context use <name>`.
Don't switch contexts without telling the user; the wrong context is the usual
cause of an empty list, so say which one you're moving to.

## Step 3 — Does Willow think the server is available to this user?

Using the Willow MCP (find tools with `willow tools grep server` or
`willow tools grep connect`, read the schema with `willow tools info`, then
call read-only ones), answer for the missing server:

| Finding | Meaning | Fix |
| --- | --- | --- |
| Not listed | Not granted to this user | Ask the admin for access. Not a bug. |
| Listed, not connected | Connection didn't finish | **Connect** it in Willow (`triage-willow-auth` if it fails) |
| Listed, **disabled** | Turned off, so its tools vanish immediately | Click **Enable** on the server card |
| Connected, 0 tools | Upstream or auth problem on that server | `triage-willow-auth` (re-authenticate), then escalate with evidence |

No suitable Willow MCP tool? Ask the user to open the **MCP Servers** page and
read off the status dot, **Enable**/**Disable** and the tool count.

## Step 4 — Is the client holding an old tool list?

A client keeps the tool list it fetched when it connected. Changing a server's
API keys while a session is open leaves the client with the old shape:

- two or more keys: every tool takes a required `account` argument;
- one key: the `account` argument is gone;
- a call naming a key that no longer exists fails with
  `Unknown account "<name>"` and lists the keys that do.

`Unknown account` is the signature of a stale list. Don't retry the call.

**Fix** (any one; the first is universal):

1. Start a new chat or session.
2. Quit and fully reopen the client.
3. CLI: `willow tools refresh` (clears the cached catalog; the next command
   fetches a fresh one). The same applies after adding or removing a server.

Per-client refresh steps (Cursor off/on, Claude Code `/mcp` → Reconnect, VS Code
**Restart Server**, ...) are in `triage-willow-client-setup`.

**Verify:** with two or more keys each tool shows an `account` parameter naming
the user's keys; with one key there is none.

## Step 5 — Client never picked up the config

If it is a brand new setup and the client lists nothing at all, the entry may
be ignored. Cursor needs `"type": "http"`; most clients need a full restart.
Use `triage-willow-client-setup`.

## Still empty?

Run the `triage-willow` skill's evidence script and escalate with its report.
Include which of the five steps you ruled out, and the server's tool count as
Willow reports it versus what the client shows.
