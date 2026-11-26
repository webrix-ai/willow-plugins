---
name: triage-willow-client-setup
description: >-
  Fix Willow MCP client configuration and connection problems: Cursor silently
  ignoring the Willow entry (missing "type": "http"), Claude Code showing Willow
  as disconnected, wrong or http:// gateway URL, connection refused, a client
  that needs a restart or reconnect to pick up changes, VS Code, Codex, OpenCode,
  Claude Desktop, ChatGPT and Devin Desktop refresh steps. Use when a Willow MCP
  server was added to an AI client but the client doesn't see or reach it.
---

# Triage: client configuration and connection

Check the URL first; it explains more failures than everything else combined.

## Step 1 — Is the URL right?

The correct URL is the one **Connect MCP** shows for this user's org. Its shape:

```text
https://<org>.withwillow.ai/mcp                  # everything the user can use
https://<org>.withwillow.ai/mcp?mcp=<server>     # one server only
https://<org>.withwillow.ai/mcp?toolkit=<name>   # one toolkit only
```

Scoped URLs also appear in a path form, for example `/mcp/mcp/<server>` and
`/mcp/toolkit/<name>`. Both mean "only this server/toolkit".

The host can be `<org>.withwillow.ai`, `<org>.mcp-s.com`, a region-specific or
a custom domain, so don't "correct" a host that differs from this example.
Compare it character by character with what **Connect MCP** shows. Look for:

- `http://` instead of `https://`, or a mangled scheme such as `ttps://`
- a typo in the org or server name (this fails *silently*)
- a missing `/mcp` path
- a scope (`?mcp=`, `?toolkit=`, `/mcp/mcp/...`, `/mcp/toolkit/...`) the user
  didn't intend

Find what the client actually has by running the `triage-willow` evidence
script; it prints only each Willow entry's type and URL (never headers or
tokens) and flags a non-`https://` URL, a missing `/mcp` path, and a missing
`type`. Don't `cat` client config files yourself: they can hold secrets.

The same script probes each URL the way a client does before signing in:

| Probe | Meaning |
| --- | --- |
| `401` + OAuth challenge | The URL reaches a Willow gateway; sign-in is next. Normal. It can't tell a wrong org or server name from a right one, so still compare with **Connect MCP**. |
| `200` + a web page | The URL is the portal, not the MCP endpoint: add `/mcp`. |
| `404` | Typo in the path. |
| `301` and similar | Usually `http://` → `https://`. Use the final `https://` URL in the client. |
| `000` / timeout / TLS error | See Step 3. |

## Step 2 — Fix the entry for this client

### Cursor

`~/.cursor/mcp.json` (or `.cursor/mcp.json` in the project):

```json
{
  "mcpServers": {
    "willow": {
      "type": "http",
      "url": "https://<org>.withwillow.ai/mcp"
    }
  }
}
```

`"type": "http"` is **required**. Cursor silently ignores entries without it,
which looks like "no tools" with no error. After editing, **fully restart
Cursor**.

### Claude Code

Run `/mcp` in a session. If Willow shows **disconnected**, re-add it:

```bash
claude mcp add --transport http willow https://<org>.withwillow.ai/mcp
```

Then choose **Reconnect** in `/mcp`, and start a new session or run `/clear`.

### Other clients: refresh after a change

| Client | How to reload the connection |
| --- | --- |
| Cursor | **Settings → Tools & MCP**: switch Willow off and on, start a new chat; restart Cursor if needed |
| Claude Code | `/mcp` → `willow` → **Reconnect**, then new session or `/clear` |
| Claude Desktop | **Settings → Extensions**: switch the Willow extension off and on, new chat; quit and reopen if needed |
| Claude Web | New conversation (old ones keep their tools). Still wrong: **Customize → Connectors → Willow**, disconnect, reconnect |
| ChatGPT | New chat. Still wrong: **Settings → Apps → Willow**, Refresh if offered, else remove and re-add |
| VS Code (Copilot) | Command Palette → **MCP: List Servers** → **Willow** → **Restart Server**; new chat in agent mode |
| Codex | `/mcp` to see what's loaded, then restart or start a new session |
| OpenCode | `/mcps`, switch **willow** off and on, new session |
| Devin Desktop (formerly Windsurf) | MCP settings: refresh or toggle Willow, new chat; restart if needed |

**Universal fallback for any client:** start a new chat or session; if that
fails, quit and reopen the client.

## Step 3 — Connection refused or can't reach the server

1. The internet works and the URL uses `https://`.
2. The evidence script's endpoint probe: `401` = reachable; `000`, a timeout or
   a TLS error = network, VPN, proxy, DNS or certificate problem on this
   machine. The `curl:` line under the probe says which (for example `Could not
   resolve host`, or a certificate error). With a corporate proxy or custom CA,
   `HTTPS_PROXY` and `NODE_EXTRA_CA_CERTS` matter for Node-based clients.
   Try another network (a phone hotspot) to separate a company network block
   from a Willow problem.
3. If the host doesn't resolve, ask the admin to confirm the org's gateway
   domain is deployed and active. A `403`, `429` or `5xx` from the probe means
   something is blocking or failing the request: report the exact code.

## Step 4 — Connected but nothing works yet

If the client now reaches Willow but lists no tools or answers `401`:

- `401` or an Authorize page never finished → `triage-willow-auth`
- Connected, tools empty or stale → `triage-willow-missing-tools`

## Making edits

Editing a client's config file is a change to the user's setup: show the exact
before/after, ask first, and only touch the Willow entry. Back up nothing
silently and delete nothing.
