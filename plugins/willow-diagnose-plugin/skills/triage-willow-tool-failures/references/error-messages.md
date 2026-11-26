# Willow tool-call messages: what they mean and who fixes them

These are the texts the Willow gateway puts in a tool result or an HTTP error.
`<server>`, `<tool>` and `<toolkit>` stand for real names. Most messages
already say who can fix them; believe the message.

Who fixes it: **User** = the person in front of you, **Admin** = their Willow
admin, **Service** = the owner of the upstream system (GitHub, Jira, ...).

## Access and availability (HTTP 403 / 404)

| Message | Code | Meaning | Who fixes it |
| --- | --- | --- | --- |
| `You do not have access to this MCP server` | `MCP_ACCESS_DENIED` | The server isn't assigned to this user | Admin grants access |
| `MCP server is disabled` | `MCP_DISABLED` | The admin turned the whole server off | Admin |
| `MCP server is not published` | `MCP_NOT_PUBLISHED` | The server is still a draft | Admin publishes it |
| `MCP server not found` | `MCP_NOT_FOUND` | No server with that slug: a typo in the URL or call, or it was removed | User fixes the slug; else Admin |
| `Tool not found` | `TOOL_NOT_FOUND` | The tool doesn't exist **or the admin disabled that one tool** | Admin, if the user needs it |
| `Toolkit not found` | — | Wrong toolkit slug | User fixes the slug |
| `This toolkit is not assigned to you` / `You do not have access to this toolkit` | — | Toolkit not shared with this user | Admin |
| `Tool is not part of this toolkit` | `TOOL_NOT_IN_TOOLKIT` | The connection is scoped to a toolkit that doesn't include the tool | User connects without the toolkit scope; or Admin adds the tool |
| `You do not have access to any MCP server in this toolkit` | — | Toolkit exists but none of its servers are assigned to the user | Admin |
| `Not permitted to call this tool` | — | Generic refusal for this user or this call | Admin, with the exact time |
| A refusal for this **AI client** (code `MCP_CLIENT_NOT_ALLOWED`) | `MCP_CLIENT_NOT_ALLOWED` | The server is restricted to certain AI tools, and this client isn't one | Use an allowed client, or Admin widens the server's **Allowed AI Tools** |
| `Organization is inactive` | — | The org is deactivated | Admin / Willow support |
| `User account is deactivated` | `USER_DEACTIVATED` | This user's Willow account is off | Admin |
| `Access denied: your IP address (<ip>) is not permitted by this organization's IP access filter` | HTTP 403 | The org only allows certain networks | User connects from the office network or VPN; Admin updates the IP filter |
| `Rate limited` / HTTP 429 | `RATE_LIMITED` | Too many calls | Wait and retry; reduce bulk calls |

## The user's own connection to a server

| Message (starts with) | Meaning | Who fixes it |
| --- | --- | --- |
| `Sign in to <server> to use this tool. ... Show this link to the user: <url>` | The user never connected that server, or the connection lapsed | **User** opens the link and connects |
| `Failed to generate access token for <server>. Please reauthorize at: <url>` | The stored connection can't produce a token | **User** opens the link (or **Re-authenticate** on the server card) |
| `<server> has no valid credential for this user — it authenticates per person with credentials the user supplies themselves ... Show this link to the user so they can add them: <url>` | Per-user API key or credentials missing or rejected | **User** adds a valid key at the link |
| `Your single sign-on session for <server> has expired. Sign in again to continue. Show this link to the user: <url>` | The server passes the user's Willow SSO session through, and it expired | **User** signs in again at the link |
| `<server> rejected this call because the credential this user supplied does not cover it, not because it expired ...` | The user's own key lacks a permission | **User** issues a new key with the missing permission and saves it at the link. Re-saving the same key won't help. |
| `<server> rejected this call for a missing OAuth scope, not an expired credential — signing in again will not change the result ... A Willow admin needs to reconnect the <server> integration ...` | The org's OAuth app lacks a scope | **Admin**. Don't send the user round a sign-in loop. |
| `<server> could not be authenticated, and no sign-in can fix it: ... Tell the user that <server> is not configured correctly in Willow ...` | An org-wide credential is wrong, or the server sends none | **Admin** or Willow support. Don't show any sign-in link. |
| `The API key placeholder for "<server>" was not filled. Connect it in your settings to add your key.` | The user hasn't entered their key yet | **User** adds the key from the server card |
| `Unknown account "<name>"` | Stale tool list after API keys changed | **User** refreshes the client's tool list, then retries with a listed key |
| `<server> runs on a Willow Tunnel gateway, and its run service is not connected. Ask your admin to start it.` | A self-hosted connector is offline | **Admin** |

## Guards, conditions and approvals

| Message (starts with) | Meaning | Who fixes it |
| --- | --- | --- |
| `<reason>` + `Please approve the request at: <url>` (code `TOOL_PENDING_APPROVAL`). The reason is `This tool requires approval before execution.`, `This request was flagged by the following guard(s) and requires approval before execution: <guard>.`, or a custom message | Human-in-the-loop check. The approval belongs to the user who made the call, and it expires. | **User** opens the link, reviews the arguments, approves or declines. Never approve for them. Then retry the call. |
| `Blocked by Willow guard(s): <guard>. This content violates your organization's security policy.` / `Blocked by your organization's Willow security policy.` / `Tool blocked by organization's guardrails` | A guard denied the request | Not a fault. **Admin** reviews the guard if it's wrong. Don't rephrase the request to get around it. |
| `[Output withheld by Willow guard(s): <guard>. The tool ran, but its result was blocked ...]` | The call **ran** (it may have changed something); only its output was hidden | Don't re-run a write. **Admin** if wrong. |
| `This tool call was blocked by the "<name>" condition.` / `Tool call blocked by a condition` | An admin rule about this tool's arguments or context | **Admin**, naming the condition |
| `The "<name>" condition could not be evaluated, so the call was blocked.` | The rule failed to run; blocked to be safe | **Admin** / Willow support, with the time |
| `Access blocked by your organization's risk policy.` | The user's risk level blocks this tool | **Admin** |

## The upstream service answered

Anything else, especially in the service's own words or with its own HTTP
status, is the upstream system talking (`UPSTREAM_TOOL_ERROR`):

| Upstream says | Meaning | Who fixes it |
| --- | --- | --- |
| `403`, forbidden, permission denied (and not a scope message above) | The user's account on that service can't see or do this | **Service** owner grants it. Don't look for a workaround. |
| `404`, not found | Wrong ID, or not visible to this account | **User** verifies the ID with a read-only listing call |
| `400`, validation error | Bad arguments for that service | **User/agent** fixes the arguments against the schema |
| Timeout, `5xx` | The service is slow or down | Retry once; if it repeats, escalate with the time |
