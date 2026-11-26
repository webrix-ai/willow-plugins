# The Willow User MCP — what to call and how to read it

The catalog connector `willow-user` ("Willow User") is the API behind each
org's portal, exposed as MCP tools. An org admin adds it like any other server,
so its slug in a given org is whatever they named it (often `willow-user`).
Every call runs **as the user who makes it**: the gateway issues a short-lived
token for that user, so results always mean "for this user", never org-wide.

Tool names can show up with a prefix in the client (for example
`willow-user__check_connection`). With Dynamic MCP, call them through
`execute_tool` with `mcp_slug` set to the Willow User server's slug and
`tool_slug` set to the name below.

## Read-only tools for triage

### `list_user_mcp_servers`

Servers this user can reach.

| Argument | Type | Notes |
| --- | --- | --- |
| `search` | string | Keywords, e.g. `"jira"`. Matches name, slug, description and tool names. |
| `include_tools` | boolean | Adds each server's **enabled** tools (name, slug, description) |
| `limit` | number | Default 50, max 100 |
| `cursor` | string | From the previous response's `pagination.nextCursor` |

Each item has `slug`, `name`, `description`, `status` (`active` or `draft`),
`auth_type`, `tools_count` (enabled tools only), `is_local_mcp`, and
`connections` (the `http` URL to use for that server alone, in the org's
format). The `slug` is what the other tools take as `integration`.

How to read it:

- Server missing: not assigned to this user, not published, or disabled.
  The admin decides.
- `tools_count: 0`: every tool is disabled or the server isn't set up. Admin.
- Present, but missing from the client: the problem is on the client side
  (scope, Default MCP, stale list). See `triage-willow-missing-tools`.
- `connections[].url` is the correct scoped URL. Compare it with the client's.

### `check_connection`

| Argument | Type | Notes |
| --- | --- | --- |
| `integration` | string, required | Server slug from `list_user_mcp_servers` |

Returns `{ "data": true | false }`. `true` means this user has a stored
**OAuth** sign-in for that server whose access or refresh token hasn't expired.

`false` is only meaningful for OAuth servers (`auth_type` from
`list_user_mcp_servers`). It is **always** `false` for:

- API-key servers (`auth_type: "apiKey"`), even when the user's key works;
- servers with no per-user sign-in;
- a slug that doesn't exist (check the spelling against
  `list_user_mcp_servers`).

How to read it:

- `false` on an OAuth server: the user never finished **Connect**, or the
  sign-in expired. Use `get_auth_url` to get a fresh link.
- `true` but calls still fail: the token is there but may have been revoked
  upstream or may lack a permission. Read the tool's error
  (`triage-willow-tool-failures`).

### `get_auth_url`

| Argument | Type | Notes |
| --- | --- | --- |
| `integration` | string, required | Server slug |

Returns `{ "data": "<url>" }`: a link that starts the sign-in for that server
**as this user**. Show it to the user and let them open it. Don't open it for
them, and don't pass it to anyone else.

- `403` with `MCP server is not available`: this user may not connect this
  server. Admin.

### `list_user_toolkits`

`limit`, `cursor`. Lists the toolkits this user can use (own and org-wide),
with `slug`, `name`, `description` and `status`. Use it to check a
`?toolkit=` / `/mcp/toolkit/<name>` scope, or a `Toolkit not found` error.

## The one write tool used in triage: `submit_issue`

Opens a Willow support ticket **under the user's name and email**. Only call
it after the user has read the final text and said yes.

| Argument | Type | Notes |
| --- | --- | --- |
| `title` | string, required | One-line summary |
| `body_html` | string, required | The escalation report as HTML; wrap evidence in `<pre>` |
| `tags` | string[] | Optional |
| `priority` | string | **Omit.** The connector lists `medium`, which the endpoint rejects (it accepts `urgent`, `high`, `normal`, `low`). |

Returns the ticket `id` and `number`. Give the number to the user.

## Don't call while triaging

`create_user_toolkit`, `update_user_toolkit`, `delete_user_toolkit`,
`create_user_skill` and `update_user_skill` change the user's resources.
`list_user_skills`, `list_user_commands` and `list_user_plugins` are
read-only, but not relevant to connection problems.
