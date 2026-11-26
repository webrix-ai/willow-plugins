---
name: triage-willow-tool-failures
description: >-
  Triage Willow tool calls that are listed but fail: a request held on a human
  approval popup or blocked by a guard, schema or INVALID_PARAMS errors,
  MISSING_ARGUMENT or INVALID_JSON_ARGUMENTS, TOOL_DISABLED, TOOL_NOT_FOUND,
  403 or permission denied, `Unknown account`, calls that fail after a server was
  disabled or disconnected, and willow CLI exit codes 1 to 4. Use when the tool
  exists in the list but calling it doesn't work.
---

# Triage: a tool call fails, is blocked, or is waiting

The tool is visible, so discovery and sign-in are mostly fine. Find out *which
layer* answered with the failure, then fix that layer.

## Step 1 — Read the exact error

Get the full text, not a paraphrase. With the CLI, errors look like
`Error [TYPE]: message` followed by a `Suggestion:` line, and the process exit
code says which layer failed:

| Exit code | Layer | Go to |
| --- | --- | --- |
| 1 | Client side: bad arguments or config | Step 2 |
| 2 | The tool ran and failed | Step 4 |
| 3 | Network: connection failed | `triage-willow-client-setup` Step 3 |
| 4 | Not signed in | `triage-willow-auth` |

## Step 2 — Bad input (client side)

| Error | Meaning | Fix |
| --- | --- | --- |
| `INVALID_PARAMS`, `MISSING_ARGUMENT` | Arguments don't match the schema | `willow tools info <tool>` and compare. Fix names, required fields, types. |
| `INVALID_JSON_ARGUMENTS` | The argument string isn't valid JSON | Quote string keys, wrap the whole arg in single quotes, or pipe JSON on stdin |
| `TOOL_NOT_FOUND` | Wrong name, or the tool isn't in the active context | Use the "Did you mean" suggestion; `willow tools grep <word>`; check `willow context list` |
| `TOOL_DISABLED` | The tool is in `disabledTools` of the user's own CLI config | Tell the user; removing it is their call (`willow config edit`) |
| `Unknown account "<name>"` | Stale tool list: a key was added, removed or renamed since the client connected | Refresh the tool list, then retry with a key from the list the error prints. See `triage-willow-missing-tools` Step 4. |

Don't retry the same failing call. Change the input based on the schema.

## Step 3 — Blocked or held for approval

A request can be stopped before it runs, by an organization guard or an
approval rule. Signs: the call hangs, a **human approval popup** appears
(options: allow once, always allow, deny), or the error mentions a blocked
request or policy.

- **Popup present:** the user decides. Never approve on their behalf. *Allow
  once* is the cautious choice; *always allow* is remembered (for browser
  requests, by hostname).
- **Popup never appears** (client or extension not loaded): fully restart the
  client or browser so policy is re-read, and confirm the extension is active
  on the page.
- **Hard denial** (blocked, no popup): this is policy, not a fault. Don't work
  around it; give the user the exact message and tell them to ask their admin
  to review the rule that matched.

## Step 4 — The tool ran and failed

Treat the message as coming from the upstream service (GitHub, Jira, ...) and
read it as that service would say it.

| Message | Likely cause | Fix |
| --- | --- | --- |
| `401`, "unauthorized", "token expired" from that service | The user's connection to that server lapsed | **Re-authenticate** the server (`triage-willow-auth` Section B) |
| `403`, "forbidden", "permission denied" | The user's account on that service, or their Willow access, lacks permission | Don't escalate privileges. Ask the service owner or the Willow admin to grant it. |
| `404`, "not found" | Wrong identifier or the resource isn't visible to this account | Verify the ID with a read-only listing call |
| Timeout, slow, intermittent | Slow upstream service, or gateway latency | Retry once; if repeated, collect evidence |
| Works for others but not this user | Per-user connection or access | Compare with the Willow MCP's view of this user's connection |
| Server vanished mid-conversation | It was disabled or disconnected; its tools go away immediately | **Enable** or reconnect it in Willow |

## Step 5 — CLI only: does it hang?

`Daemon request timeout` is a local daemon problem, not a tool failure. Use
`diagnose-willow`.

## Using the Willow MCP

Read-only lookups help here: the user's recent calls (success rate, errors,
which client) and whether the server is connected and enabled for them.
Find the tools with `willow tools grep usage` / `willow tools grep connect`,
read each schema with `willow tools info`, and call only read-only ones. If
none exist, don't invent one: ask the user to check **Analytics** and the
**MCP Servers** page in Willow.

## Escalate

Run the `triage-willow` evidence script and fill its report. For a tool failure
always add: the tool name, the exact arguments (with secrets removed), the exact
error text, the exit code, and the time it happened so support can find the call
in the logs.
