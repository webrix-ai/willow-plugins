---
name: triage-willow-tool-failures
description: >-
  Triage Willow tool calls that are listed in an AI client (Cursor, Claude Code,
  Claude Desktop, VS Code, Codex, ChatGPT, ...) but fail: "Please approve the
  request at", "Blocked by Willow guard(s)", "Sign in to <server> to use this
  tool", "Failed to generate access token ... reauthorize", "You do not have
  access to this MCP server", "MCP server is disabled", "Tool not found",
  "Access denied: your IP address", "no sign-in can fix it", `Unknown account`,
  invalid-parameter errors, upstream 401/403/404, plus willow CLI error types
  and exit codes. Use when the tool exists in the list but calling it doesn't
  work.
---

# Triage: a tool call fails, is blocked, or is waiting

The tool is visible, so discovery and sign-in are mostly fine. Find out *which
layer* answered with the failure, then fix that layer.

**Willow's messages usually name the fix.** They are written for the AI to
relay: many end with a link to show the user, or say plainly that only an admin
can fix it ("no sign-in can fix it", "A Willow admin needs to ..."). Read the
message literally and follow it. Don't override it with a generic "try signing
in again".

**What you need from the user** (ask for what isn't already known, at most
three at once):

- The **exact** message: paste or screenshot. "It failed" isn't enough; the
  wording decides everything below.
- Which tool, on which server, from which AI client.
- Does it fail every time or sometimes? Does the same call work for a
  colleague or in another client?
- For a write (create, update, send, delete): did it maybe happen anyway?
  Check before anyone retries.

## Step 1 — Get the exact text and classify it

Copy the full message, not a paraphrase. Then match it against
[references/error-messages.md](references/error-messages.md), which lists every
known Willow message with its meaning and who fixes it. The groups:

| The message is about | Typical start | Go to |
| --- | --- | --- |
| Access or availability | `You do not have access ...`, `MCP server is disabled`, `... not published`, `Tool not found`, `... toolkit ...`, `Access denied: your IP address ...` | Step 2 |
| The user's own connection to that server | `Sign in to <server> ...`, `Failed to generate access token ...`, `... single sign-on session ... expired`, `... credential this user supplied ...`, `Unknown account` | Step 3 |
| A guard, condition or approval | `Please approve the request at: ...`, `Blocked by Willow guard(s) ...`, `... blocked by the "<name>" condition`, `[Output withheld by Willow guard(s) ...]` | Step 4 |
| The arguments | invalid params, missing required field, invalid JSON | Step 5 |
| The upstream service itself | the service's own words or status code | Step 6 |
| The client can't reach Willow at all (disconnected, 401 on every tool) | — | `triage-willow-auth` / `triage-willow-client-setup` |

CLI users get structure for free: `Error [TYPE]: message` plus a `Suggestion:`
line, and the exit code names the layer (1 = arguments or config, 2 = the tool
ran and failed, 3 = network, 4 = not signed in). `Daemon request timeout` is
the CLI's own problem: use `diagnose-willow`.

## Step 2 — Access and availability

These are decisions, not faults. The user can fix two of them; the rest need
the admin:

- **The user can fix:** a typo'd server or toolkit slug (`MCP server not
  found`, `Toolkit not found`), and `Tool is not part of this toolkit` (connect
  without the toolkit scope; see `triage-willow-missing-tools` Step 3).
- **Network:** `Access denied: your IP address (...) is not permitted by this
  organization's IP access filter`. Connect from the office network or VPN, or
  ask the admin to update the filter.
- **The admin must fix:** not assigned, disabled, not published, a disabled
  tool, a server restricted to other AI clients, a deactivated user or org.
  Give the user the exact message and the server name to send.

## Step 3 — The user's own connection to that server

Most of these messages carry a link. **Show the link to the user** and have
them open it. Don't open it for them, and don't paste credentials anywhere.

| Message | Action |
| --- | --- |
| `Sign in to <server> to use this tool ... <url>` | User connects at the link, then retries |
| `Failed to generate access token for <server>. Please reauthorize at: <url>` | User re-authorizes at the link (same as **Re-authenticate** on the server card) |
| `... single sign-on session for <server> has expired ... <url>` | User signs in again at the link |
| `... credentials the user supplies themselves ... <url>` / `The API key placeholder ... was not filled` | User adds a valid key for that server |
| `... the credential this user supplied does not cover it ...` | User creates a new key **with the missing permission**. Re-saving the same key won't help. |
| `... missing OAuth scope ... A Willow admin needs to reconnect ...` | Admin. Don't send the user to sign in again: it can't help. |
| `... could not be authenticated, and no sign-in can fix it ...` | Admin or Willow support. Show no sign-in link. |
| `Unknown account "<name>"` | Stale tool list: refresh the client (`triage-willow-missing-tools` Step 5), then retry with a key the error lists |
| `... runs on a Willow Tunnel gateway, and its run service is not connected` | Admin starts the tunnel |

No link in the message, or it expired? If the org added the Willow User MCP,
`get_auth_url` with `integration: "<server slug>"` returns a fresh sign-in link
for this user. A `403 "MCP server is not available"` there means the user isn't
allowed that server. `check_connection` tells you whether an OAuth sign-in is
stored; it is always `false` for API-key servers.

If the admin changed the server's sign-in method, **Re-authenticate** keeps the
old one: **Disconnect**, then **Connect** (`triage-willow-auth` Section B).

## Step 4 — Guards, conditions and approvals

- **`Please approve the request at: <url>`.** The call is waiting for a human
  check. The approval belongs to the user who made the call, and it expires.
  Show the link. The user reviews the arguments and approves or declines, and
  then the call is retried. Never approve on their behalf. Some clients show an
  approval card in the chat instead of a link.
- **`Blocked by ...`, `... blocked by the "<name>" condition`, `Access blocked
  by your organization's risk policy`.** This is policy, working as intended.
  Don't rephrase or split the request to get past it. If the user thinks it's
  wrong, they send the exact message (including the guard or condition name) to
  their admin.
- **`[Output withheld by Willow guard(s): ...]`.** The tool **ran**; only its
  result was hidden. Don't re-run it, especially a write.
- **`The "<name>" condition could not be evaluated, so the call was blocked.`**
  An admin-side rule failed. Escalate with the time.

## Step 5 — Bad arguments (before the tool ran)

Compare the call with the tool's schema. In an MCP client it's in the tool
definition; with Dynamic MCP, `get_tool_details`; with the CLI,
`willow tools info <tool>`. Fix names, required fields and types. Don't retry
the same failing call: change the input.

## Step 6 — The upstream service answered

The message is in the service's own words (GitHub, Jira, ...):

| Upstream says | Meaning | Fix |
| --- | --- | --- |
| `403`, forbidden, permission denied | The user's account on that service can't see or do this | The service owner grants it. Don't look for a workaround. |
| `404`, not found | Wrong ID, or not visible to this account | Verify with a read-only listing call |
| `400`, validation error | Arguments wrong for that service | Fix against the schema |
| Timeout, `5xx`, slow | Service slow or down | Retry once; if it repeats, escalate with the time |
| Works for others, not this user | Per-user connection or access | Compare this user's connection (Step 3) |

## Escalate

Run the `triage-willow` evidence script and fill its report. For a tool failure
always add the tool and server name, the exact error text, the arguments (with
secrets removed), which client, and the time, so support can find the call in
the logs. A write that may have run (output withheld, timeout) must be called
out.
