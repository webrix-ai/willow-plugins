---
name: triage-willow
description: >-
  Entry point for triaging any "Willow isn't working" report from an end user:
  no tools showing, 401 / Unauthorized, OAuth popup or localhost 404 problems,
  a client that won't connect, tool calls failing or blocked, a stale tool list.
  Classifies the symptom, collects redacted read-only evidence, checks
  server-side state through the Willow MCP, routes to the matching
  triage-willow-* skill, and builds a support report when the issue is not
  resolved. Use first whenever a user says Willow, an MCP server or a tool is
  broken and the cause is unknown.
---

# Triage a Willow problem

Goal: find which known issue the user has, fix it with the smallest safe step,
and, if it is not a known issue, hand support a report they can act on without
a follow-up question.

## Ground rules

- **Read-only first.** Observe before changing anything. Every change (kill a
  process, edit a config file, disconnect or re-authenticate a server) needs the
  user's go-ahead, and you say what it will do.
- **Never print secrets.** Don't run `willow auth token`, don't `cat`
  `~/.config/willow/auth.json` or a client config that holds headers. Use the
  bundled evidence script, which redacts tokens, JWTs and emails.
- **Ask one question at a time**, and only when the answer changes the next
  step. Most of what you need is discoverable.
- **Access questions go to the admin.** "Why can't I see X?" or "Why don't I
  have access to Y?" is usually an admin-side permission, not a bug.

## Step 1 — Classify the symptom

Pick the row that matches the user's words. If two match, take the one higher in
the table: an auth problem hides everything below it.

| What the user sees | Skill to use |
| --- | --- |
| `Unauthorized`, `401`, "authorization never finished", Authorize page loops, 404 on `localhost` after signing in, popup blocked on **Connect**, `willow auth` exit code 4, a server that needs **Re-authenticate** | `triage-willow-auth` |
| Client config problem: Cursor ignores the entry, Claude Code shows `disconnected`, wrong or `http://` URL, client needs restart, connection refused | `triage-willow-client-setup` |
| Connected, but "no tools", a server or tool is missing, tool names or `account` choices look old, `Unknown account "<name>"`, empty `willow tools list` | `triage-willow-missing-tools` |
| A tool is listed but the call fails, is blocked, waits on an approval, returns a schema or permission error | `triage-willow-tool-failures` |
| `willow` CLI itself hangs, `Daemon request timeout`, `willow doctor` FAILs | `diagnose-willow` |
| None of the above | Continue at Step 4 and escalate |

If a matching skill isn't installed, follow the same checks from the table in
[references/known-issues.md](references/known-issues.md).

## Step 2 — Collect evidence (read-only)

```bash
bash scripts/collect-evidence.sh
```

It prints, with secrets redacted: OS and Node versions, `willow --version`,
`willow auth status` (exit code), `whoami`, contexts, daemon state,
`willow doctor`, the Willow entries of common MCP client configs (type and URL
only), and an unauthenticated reachability probe of the gateway.

Read it for the three facts that decide most cases:

1. **Is the gateway reachable?** A `401` from the probe is *good* here: the
   gateway answered and wants a token. `000`, a timeout or a TLS error means a
   network, VPN, proxy or DNS problem.
2. **Is the user signed in?** `auth status` exit 0 = yes, 4 = no.
3. **Does the client point at the right place?** URL uses `https://`, the right
   org host, and contains `/mcp`. A scope (`?mcp=<server>`, `?toolkit=<name>`,
   `/mcp/mcp/<server>`, `/mcp/toolkit/<name>`) limits the client to that one
   server or toolkit.

## Step 3 — Check server-side state with the Willow MCP

If the Willow MCP is connected in this session, use it to see what Willow
believes about this user. These are read-only lookups.

Don't guess tool names. Find them first:

```bash
willow tools grep connect     # or: server, status, toolkit, usage, me
willow tools info <tool>      # read the schema before calling
```

(In an MCP client, search the tool list for the same keywords.)

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
Where:          <client + version> / <CLI or portal> / <page URL if portal>
Org / user:     <org slug>, <signed-in identity as shown by whoami>
Started:        <when, and what changed just before>
Expected:       <what should happen>
Actual:         <exact error text, copied, not paraphrased>
Already tried:  <each step and its result>
Evidence:       <redacted output of collect-evidence.sh>
```

Rules for the report: exact error text, one issue per report, no tokens, and
state which steps changed the behavior even slightly.

## Quick reference

| Task | Command |
| --- | --- |
| Gather redacted evidence | `bash scripts/collect-evidence.sh` |
| Sign-in state (0 ok / 4 re-login) | `willow auth status` |
| Who am I, which org and context | `willow auth whoami`, `willow context list` |
| Search tools by keyword | `willow tools grep <word>` |
| Drop the cached tool list | `willow tools refresh` |
| Whole-environment check | `willow doctor` |
