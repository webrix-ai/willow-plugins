---
name: triage-willow-missing-tools
description: >-
  Fix Willow connections that work but show no tools, or the wrong ones: an AI
  client (Cursor, Claude Code, Claude Desktop, VS Code, Codex, ChatGPT, ...)
  says "no tools available", shows only search_tools / execute_tool instead of
  the real tools, an MCP server or tool is missing, the willow CLI shows tools
  the client doesn't, tool names or API-key `account` choices look out of date,
  `Unknown account "<name>"`, or only one server's or toolkit's tools appear.
  Use when the user is connected and signed in but the tool list is empty,
  partial or stale.
---

# Triage: no tools, missing tools, or a stale tool list

The connection exists, but the tools the user expects aren't there. Work down
the checks in order and stop at the first one that explains it. All checks are
read-only until the **Fix** at the end of a step.

**What you need from the user** (ask for what isn't already known, at most
three at once):

- Which AI client, and which server or tool they expect to see.
- Did it ever show up? If yes, what changed (admin change, new key, new
  setup)?
- Does it show up somewhere else: another AI client, the `willow` CLI, the
  Willow portal, a colleague?

Don't ask what the lookups in Step 4 can answer, such as whether the server is
available to them.

## Step 1 — What exactly does the client list?

Ask the client what Willow tools it has (or look at its MCP panel).

**Exactly these five tools?**
`search_tools`, `get_mcp_servers`, `get_mcp_tools`, `get_tool_details`,
`execute_tool`

That is **Dynamic MCP**, and nothing is broken. New organizations default to
it: a URL that names no server or toolkit lists these five discovery tools,
and the AI looks up and runs the real tools through them. It keeps the client's
context small.

- To use it, ask for the task in plain words. The AI calls `search_tools`
  (for example "create jira issue"), then `execute_tool`.
- To see one server's real tools in the list, connect with a URL that names it
  (Step 3).
- To change what an unscoped URL lists, the admin changes the org's
  **Default MCP** setting (**All MCPs**, **Dynamic MCP** or **Default
  Toolkit**).

**Nothing at all?** Go to Step 2. **Some, but not the expected ones?** Go to
Step 3.

**The `willow` CLI shows more than the client?** Expected. The CLI ignores
the Default MCP setting and always gets every tool the user can access.

## Step 2 — Is it really signed in?

An unauthenticated connection looks exactly like "no tools". If the user
closed the browser Authorize page without clicking **Authorize**, the
connection was never authenticated.

- Look at the client's own status for the Willow entry (Claude Code: `/mcp`;
  Cursor: **Settings → Tools & MCP**; VS Code: **MCP: List Servers**; Codex:
  `/mcp`). Anything other than connected/running points at sign-in.
- Not connected or "needs authentication" → use `triage-willow-auth`, then come
  back.
- CLI users: `willow auth status` (exit 4 = not signed in).

## Step 3 — What scope is the client asking for?

What the gateway lists depends on what the connection names, in this order:

1. **A server or toolkit named in the connection** always wins:
   - query: `?mcp=<server>` or `?toolkit=<name>`
   - path: `/mcp/<server>`, `/mcp/mcp/<server>`, `/mcp/toolkit/<name>`
   - header: `X-MCP: <server>` or `X-Toolkit: <name>`. Headers aren't visible
     in the URL; ask the user whether their config has a `headers` block.
     Don't print its values.
2. **Otherwise the org's Default MCP setting:**
   - **All MCPs**: every tool the user can reach, optionally capped at a
     number of tools. With a cap, only the most recently used tools are listed,
     so a rarely used tool can be "missing".
   - **Dynamic MCP**: the five discovery tools (Step 1).
   - **Default Toolkit**: only the tools in one toolkit the admin picked.

A **Use** button on a server card builds a URL scoped to that server; the
`triage-willow` evidence script prints the URLs in each client's config.

**Fix:** pick the connection that matches what the user wants. Use one URL per
server (`.../mcp/mcp/<server>`) to list that server's tools exactly. Use the
unscoped URL to get the org default. Changing the cap or the default is an
admin setting; changes reach clients within about 30 seconds, at their next
tool-list fetch. Say which URL you propose, and edit the config only with the
user's OK.

CLI users have the same thing in contexts: `willow context list` (starred =
active), then `willow context use <name>`. Say which context you're moving to.

## Step 4 — Does Willow make the server available to this user, in this client?

**Look it up rather than guess.** These read-only lookups answer for the
calling user only:

- **Dynamic MCP:** `get_mcp_servers` lists every server available to the user
  (name, slug, description); `get_mcp_tools` with `mcp_slug` lists one
  server's tools.
- **Willow User MCP** (if the org added it; names may carry a prefix such as
  `willow-user__`):
  - `list_user_mcp_servers` with `search: "<name>"` and `include_tools: true`
    returns `slug`, `status`, `auth_type`, `tools_count` (enabled tools only),
    the enabled tools, and `connections[].url`, the right URL for that
    server alone.
  - `check_connection` with `integration: "<slug>"` returns `true` if the user
    has an unexpired OAuth sign-in. It's always `false` for API-key servers, so
    ignore it there.
  - `list_user_toolkits` lists the toolkits the user can use.

Missing from these lookups = not available to this user. Present in the lookup
but missing from the client = a client-side problem (Steps 3, 5 and 6). If
neither tool set is available, ask the user to check the **MCP Servers** page
in Willow (status dot, **Connect**, **Enable**/**Disable**, tool count).

| Finding | Meaning | Fix |
| --- | --- | --- |
| Server not listed for the user | Not assigned to them, not published yet, or disabled by the admin | Ask the admin. Not a bug. |
| Listed, not connected (portal, or `check_connection` `false` on an OAuth server) | The user's own sign-in to it never finished or expired | **Connect** it in Willow, or have the user open the link from `get_auth_url` (`triage-willow-auth` if that fails) |
| Listed with `tools_count: 0` | Every tool is disabled, or the server isn't set up | Admin |
| Listed, shows **Enable** (portal) | The user turned it off, so its tools vanish immediately | Click **Enable** on the server card |
| Server listed but one tool missing | The admin disabled that tool, or it was removed | Ask the admin if the user needs it |
| Works in one AI client but not another | The server is restricted to certain AI tools (its **Allowed AI Tools** setting), or the other client isn't enabled for the org | Use an allowed client, or ask the admin |
| Connected, 0 tools | Upstream or auth problem on that server | `triage-willow-auth` (re-authenticate), then escalate with evidence |

## Step 5 — Is the client holding an old tool list?

A client keeps the tool list it fetched when it connected. Changing a server's
API keys while a session is open leaves the client with the old shape:

- two or more keys: every tool takes a required `account` argument;
- one key: the `account` argument is gone;
- a call naming a key that no longer exists fails with
  `Unknown account "<name>"` and lists the keys that do.

`Unknown account` is the signature of a stale list. Don't retry the call. The
same applies after a server is added, removed, enabled or disabled, or after
the admin changes Default MCP.

**Fix** (any one; the first is universal):

1. Start a new chat or session.
2. Quit and fully reopen the client.
3. Reload just the Willow connection (Cursor: switch Willow off and on in
   **Tools & MCP**; Claude Code: `/mcp` → `willow` → **Reconnect**; VS Code:
   **Restart Server**). More clients are in `triage-willow-client-setup`.
4. CLI users: `willow tools refresh` clears the cached catalog.

**Verify:** with two or more keys each tool shows an `account` parameter naming
the user's keys; with one key there is none.

## Step 6 — The client never picked up the config, or dropped tools

- A brand new setup that lists nothing: the entry may be ignored. Cursor needs
  `"type": "http"`; most clients need a full restart. Use
  `triage-willow-client-setup`.
- A very large catalog can exceed a client's limit on tools per connection, so
  the client hides some. Fix: Dynamic MCP, a per-server URL, or the admin's
  tool cap.

## Still missing?

Run the `triage-willow` skill's evidence script and escalate with its report.
Include which steps you ruled out, what the client lists, and what
`get_mcp_servers` / `get_mcp_tools` (or the portal) show for the same user.
