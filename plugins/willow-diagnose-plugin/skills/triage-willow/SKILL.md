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
| 2 | The client can reach the URL from this network | Connection refused, timeout, 404, the client "connects" to a web page, or `403` from the org's IP access filter | `triage-willow-client-setup` |
| 3 | The gateway answers `401` with an OAuth challenge, and the client fetches the sign-in metadata (`/.well-known/oauth-*`) | "Authorize never completes", nothing opens. **The `401` itself is normal here.** | `triage-willow-auth` |
| 4 | The user signs in through the browser (Authorize), the org allows this AI client, and the client stores the token | `Unauthorized` loops, `localhost` 404, blocked popup, a Willow error page (**Account Not Found**, **AI Tool Disabled**, **Client Not Approved**, ...) | `triage-willow-auth` |
| 5 | `tools/list`: Willow returns what this user may use, in this client, in scope, under the org's Default MCP setting | No tools; **only five tools** (`search_tools`, `execute_tool`, ...: Dynamic MCP, which is normal); a missing server; a stale or too-narrow list | `triage-willow-missing-tools` |
| 6 | `tools/call`: access, the user's own connection to that server, approvals and guards | A listed tool fails, is blocked or waits for approval. Willow's message usually names the fix. | `triage-willow-tool-failures` |

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
- **Look before you ask, then ask what only the user knows** (Step 0). Don't
  ask for anything the evidence script or a Willow lookup can tell you.
- **Access questions go to the admin.** "Why can't I see X?" or "Why don't I
  have access to Y?" is usually an admin-side permission, not a bug.

## Step 0 — Get what only the user can tell you

Reports usually arrive as "Willow doesn't work". Before classifying, make sure
you have these. Take what's already in the conversation, and ask for the rest,
**at most three questions per message**. Use multiple choice if your client
offers it.

| You need | Why | Ask, if unknown |
| --- | --- | --- |
| **Which AI client** (Cursor, Claude Code, Claude Desktop, VS Code, Codex, ChatGPT, the `willow` CLI, ...) | Every fix is per client, and the evidence script only sees local configs | "Which app are you using Willow from?" |
| **The exact message**, or what they see instead | It usually names the cause (see each skill's catalog) | "Can you paste the exact error, or a screenshot?" |
| **Which server or tool**, if one | Separates "nothing works" from one server | "Is it everything, or one server or tool? Which one?" |
| **Ever worked? What changed?** | New setup vs. regression (new laptop, VPN, admin change, update) | "Did this work before? Anything change around then?" |
| **Works anywhere else?** Another AI client, the Willow portal, a colleague, another network | Narrows it to the client, the user, or the network | "Does it work in another app or for a teammate?" |

Ask only when the answer changes your next step. For example, don't ask about
the network when the user pasted `You do not have access to this MCP server`:
the message already says the admin decides. When the user can't answer (no
error visible, doesn't know the client version), move on with the evidence;
don't block on it.

**Ask again later when:**

- the evidence shows several Willow entries or orgs: ask which one they use;
- a fix needs a change (edit a config, sign out, disconnect): confirm first,
  and say what it does;
- you're about to escalate: ask when it started and whether they agree to send
  the report.

## Step 1 — Classify the symptom

Pick the row that matches the user's words. If two match, take the one higher in
the table: a lower rung can't work until the ones above it do.

| What the user sees | Skill to use |
| --- | --- |
| Client config problem: entry ignored, wrong or `http://` URL, a typo, connection refused, 404, client needs restart or reconnect, Claude Code shows `disconnected` | `triage-willow-client-setup` |
| `Unauthorized`, `401` that doesn't resolve, Authorize never completes, `localhost` 404 after signing in, a Willow error page in the browser, `Access denied: your IP address`, popup blocked on **Connect**, a server needing **Re-authenticate** | `triage-willow-auth` |
| Connected, but "no tools", only `search_tools` / `execute_tool` and friends, a server or tool is missing, works in one client but not another, the CLI shows more than the client, tool names or `account` choices look old, `Unknown account "<name>"`, only one server's tools appear | `triage-willow-missing-tools` |
| A tool is listed but the call fails, is blocked, waits on an approval (`Please approve the request at`), returns `You do not have access`, `Sign in to <server>`, a schema or permission error | `triage-willow-tool-failures` |
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
| `403` + `Access denied: your IP address ...` | The org's IP access filter blocks this network: office network or VPN, or the admin updates the filter. |
| Other `403`, `429`, `5xx` | Blocked, rate limited or the gateway is failing. Try another network. |
| Discovery URLs not `200` | A proxy or firewall is blocking sign-in discovery: the usual cause of "Authorize never completes". |

## Step 3 — Check server-side state with the Willow MCP

If Willow is connected in this session, ask it what it knows about this user
instead of guessing. Two sources, both answering **for the calling user
only**:

- **The Willow User MCP** (catalog connector `willow-user`, if the org added
  it). Its read-only tools are `list_user_mcp_servers`, `check_connection`,
  `get_auth_url` and `list_user_toolkits`. Schemas, outputs and how to read them
  are in [references/willow-user-mcp.md](references/willow-user-mcp.md).
- **Dynamic MCP's own tools**, if the client lists them: `get_mcp_servers` (the
  servers this user can reach) and `get_mcp_tools` with `mcp_slug` (one
  server's tools).

The client may show the tool names with a prefix (for example
`willow-user__check_connection`). With Dynamic MCP, call them through
`execute_tool` using the Willow User server's slug from `get_mcp_servers`.
Read each schema before calling. With the `willow` CLI installed,
`willow tools servers` and `willow tools info <tool>` give the same answers.

What to look for:

| Question | Lookup | Where it points |
| --- | --- | --- |
| Is the server available to the user at all? | `list_user_mcp_servers` with `search: "<name>"` (or `get_mcp_servers`) | Missing → not assigned, not published, or disabled. Ask the admin. |
| Does it have tools? | Same, `include_tools: true` (`tools_count`) | `0` → every tool is disabled, or the server isn't set up. Admin. |
| Is the user's own sign-in to it done? (OAuth servers only) | `check_connection` with `integration: "<slug>"` | `false` → never connected or expired: `triage-willow-auth` Section B, and `get_auth_url` gives the link. Always `false` for API-key servers, so ignore it there. |
| May the user connect it? | `get_auth_url` | `403 "MCP server is not available"` → not allowed for this user. Admin. |
| Is the tool there? | `get_mcp_tools` or `include_tools: true` | Missing → disabled by the admin or removed |
| Works in a different AI client? | Ask the user | Yes → the server is limited to certain AI tools, or this client is disabled. Admin. |

None of these tools available? Say so, and ask the user to read the same facts
off the **MCP Servers** page in Willow (status dot, **Connect**,
**Enable**/**Disable**, tool count). Don't invent a tool call.

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

**Filing it for the user.** If the Willow User MCP has `submit_issue`, offer to
send the report as a Willow support ticket. It's sent under the user's own name
and email, so **show the final text and get a yes first**. Send `title` (the
summary line) and `body_html` (the report, with `<pre>` around the evidence).
Leave `priority` out: the connector lists `medium`, which the endpoint
currently rejects. Give the user the returned ticket number. Access problems
("why can't I see X") go to the org admin, not to Willow support.

## Quick reference

| Task | Command |
| --- | --- |
| Gather redacted evidence | `bash scripts/collect-evidence.sh` |
| Probe one URL by hand | `curl -sS -i -X POST "<url>" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}'` |
| Check sign-in discovery | `curl -sS -o /dev/null -w "%{http_code}\n" https://<host>/.well-known/oauth-protected-resource` |
| (CLI, optional) sign-in state | `willow auth status` (0 ok / 4 re-login) |
| (CLI, optional) drop the cached tool list | `willow tools refresh` |
