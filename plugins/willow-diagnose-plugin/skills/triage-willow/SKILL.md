---
name: triage-willow
description: >-
  Entry point for triaging any "Willow isn't working" report from an end user
  who connects an AI client (Cursor, Claude Code, Claude Desktop, VS Code,
  Codex, ChatGPT, ...) to Willow as a regular HTTP MCP server: no tools showing,
  401 / Unauthorized, the Authorize step or OAuth popup failing, a URL that
  doesn't connect, a stale tool list, tool calls failing or blocked. Classifies
  the symptom, probes the endpoint, collects redacted read-only evidence, routes
  to the matching triage-willow-* skill, and builds a support report when the
  issue is not resolved. The willow CLI is optional. Use first whenever a user
  says Willow, an MCP server or a tool is broken and the cause is unknown.
---

# Triage a Willow problem

Goal: find which known issue the user has, fix it with the smallest safe step,
and, if it is not a known issue, hand support a report they can act on without
a follow-up question.

Most users reach Willow the plain way: an MCP entry in their AI client pointing
at an HTTPS URL, signed in with a browser OAuth step. That needs no `willow`
CLI, and this skill never assumes it is installed.

## How the connection works (and where it breaks)

Every report maps to one rung of this ladder. Find the lowest rung that fails.

| # | Step | If it fails, the user sees | Skill |
| --- | --- | --- | --- |
| 1 | The client has a correct entry: `https://` URL ending in the org's `/mcp`, right `type` | Tools never appear, no error. Cursor ignores an entry without `"type": "http"`. | `triage-willow-client-setup` |
| 2 | The client can reach the URL | Connection refused, timeout, 404, or the client "connects" to a web page | `triage-willow-client-setup` |
| 3 | The gateway answers `401` with an OAuth challenge, and the client fetches the sign-in metadata (`/.well-known/oauth-*`) | "Authorize never completes", nothing opens. **The `401` itself is normal here.** | `triage-willow-auth` |
| 4 | The user signs in through the browser (Authorize) and the client stores the token | `Unauthorized` loops, `localhost` 404, blocked popup, expired sign-in | `triage-willow-auth` |
| 5 | `tools/list`: Willow returns what this user may use, enabled, in scope | No tools, a missing server, a stale or too-narrow list | `triage-willow-missing-tools` |
| 6 | `tools/call`: the user's own connection to that server, approvals and guards | A listed tool fails, is blocked or waits for approval | `triage-willow-tool-failures` |

The `willow` CLI is a seventh, separate path with its own daemon:
`Daemon request timeout` and `willow doctor` failures go to `diagnose-willow`.

## Ground rules

- **Read-only first.** Observe before changing anything. Every change (editing
  a client config, signing out, disconnecting or re-authenticating a server,
  restarting a process) needs the user's go-ahead, and you say what it does.
- **Never print secrets.** Don't `cat` client configs (they can hold headers
  and keys), token files, or CLI auth files. Use the bundled evidence script,
  which redacts tokens, JWTs and emails and prints only each Willow entry's
  type and URL.
- **Ask one question at a time**, and only when the answer changes the next
  step. Most of what you need is discoverable.
- **Access questions go to the admin.** "Why can't I see X?" or "Why don't I
  have access to Y?" is usually an admin-side permission, not a bug.

## Step 1 — Classify the symptom

Pick the row that matches the user's words. If two match, take the one higher in
the table: a lower rung can't work until the ones above it do.

| What the user sees | Skill to use |
| --- | --- |
| Client config problem: entry ignored, wrong or `http://` URL, a typo, connection refused, 404, client needs restart or reconnect, Claude Code shows `disconnected` | `triage-willow-client-setup` |
| `Unauthorized`, `401` that doesn't resolve, Authorize never completes, `localhost` 404 after signing in, popup blocked on **Connect**, a server needing **Re-authenticate** | `triage-willow-auth` |
| Connected, but "no tools", a server or tool is missing, tool names or `account` choices look old, `Unknown account "<name>"`, only one server's tools appear | `triage-willow-missing-tools` |
| A tool is listed but the call fails, is blocked, waits on an approval, returns a schema or permission error | `triage-willow-tool-failures` |
| The `willow` CLI hangs, `Daemon request timeout`, `willow doctor` FAILs | `diagnose-willow` |
| None of the above | Continue at Step 4 and escalate |

If a matching skill isn't installed, follow the same checks from
[references/known-issues.md](references/known-issues.md).

## Step 2 — Collect evidence (read-only)

```bash
bash scripts/collect-evidence.sh
```

Needs only `bash` and `curl`. Node.js and the `willow` CLI are used if present
and skipped if not. It prints, with secrets redacted:

1. **The Willow entries in the user's client configs** (Cursor, Claude Code,
   VS Code, Codex, Windsurf): type and URL only, with warnings for a URL that
   isn't `https://`, has no `/mcp`, or a Cursor entry with no `type`.
2. **An endpoint probe of each of those URLs**, exactly as a client sees it
   before sign-in, and a check of the sign-in discovery endpoints.
3. The CLI's version, sign-in state and `willow doctor`, only if it's installed.

Read the probe like this:

| Probe result | Meaning |
| --- | --- |
| `401` with a challenge | A Willow gateway answered; the client should begin sign-in. **Normal.** It does *not* prove the org host or server name is right: a wrong org also answers `401`. |
| `200` + a web page | The URL is the Willow **portal**, not the MCP endpoint: `/mcp` is missing. |
| `404` | Path typo. |
| Redirect (`301`...) | Often `http://` → `https://`. A client may drop the POST on a redirect; use the final URL. |
| `000` / timeout / TLS error | DNS, network, VPN, proxy or certificate problem on this machine. |
| `403`, `429`, `5xx` | Blocked, rate limited or the gateway is failing. Try another network. |
| Discovery URLs not `200` | A proxy or firewall is blocking sign-in discovery: the usual cause of "Authorize never completes". |

## Step 3 — Check server-side state with the Willow MCP

If the Willow MCP is connected in this session, use it to see what Willow
believes about this user. These are read-only lookups.

Don't guess tool names. Search the tool list the client already gives you for
keywords like `connect`, `server`, `status`, `toolkit`, `usage`, `me`, and read
a tool's schema before calling it. (If the `willow` CLI happens to be
installed: `willow tools grep <word>` and `willow tools info <tool>` do the
same.)

What to look for:

| Question | Where it points |
| --- | --- |
| Is the server in the user's list at all? | No → not granted to them. Ask the admin. |
| Is it connected for this user? | No → connection never finished. `triage-willow-auth`. |
| Is it enabled (not disabled)? | Disabled → the user can enable it. Tools vanish when it is off. |
| Does it have tools, and how many? | Zero → connection, auth or upstream problem. |
| Recent calls: success rate, errors, which client? | Shows whether the client reaches Willow at all. |

If no suitable tool exists, say so and ask the user to read the same facts off
the **MCP Servers** page in Willow (status dot, **Enable**/**Disable**, tool
count). Don't invent a tool call.

## Step 4 — Escalate with a useful report

When no known issue fits, or the fix didn't hold, write this and give it to the
user to send to their admin or to support (chat bubble in the Willow dashboard,
or support@withwillow.ai):

```text
Summary:        <one line, in the user's words>
Where:          <client + version> / <portal page URL, or CLI>
Org / user:     <org host from Connect MCP>, <how they sign in>
Started:        <when, and what changed just before>
Expected:       <what should happen>
Actual:         <exact error text, copied, not paraphrased>
Ladder step:    <the lowest rung (1-6) that fails, and the probe result>
Already tried:  <each step and its result>
Evidence:       <redacted output of collect-evidence.sh>
```

Rules for the report: exact error text, one issue per report, no tokens, and
state which steps changed the behavior even slightly.

## Quick reference

| Task | Command |
| --- | --- |
| Gather redacted evidence | `bash scripts/collect-evidence.sh` |
| Probe one URL by hand | `curl -sS -i -X POST "<url>" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}'` |
| Check sign-in discovery | `curl -sS -o /dev/null -w "%{http_code}\n" https://<host>/.well-known/oauth-protected-resource` |
| (CLI, optional) sign-in state | `willow auth status` (0 ok / 4 re-login) |
| (CLI, optional) drop the cached tool list | `willow tools refresh` |
