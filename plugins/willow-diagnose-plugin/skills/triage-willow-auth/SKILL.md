---
name: triage-willow-auth
description: >-
  Fix Willow sign-in and authorization problems for an AI client connected over
  HTTP MCP (Cursor, Claude Code, Claude Desktop, VS Code, Codex, ChatGPT, ...):
  "Unauthorized" or 401, the Authorize step never completing or never opening, a
  404 on localhost after signing in, a browser error page such as Account Not
  Found, AI Tool Disabled, Client Not Approved, Authorization Denied or Sign-In
  Expired, "Access denied: your IP address", "We couldn't find that
  organization" on the universal URL, a blocked OAuth popup on Connect, being
  signed out repeatedly, `willow auth status` exit code 4, a server stuck on an
  old auth method, or Re-authenticate not helping. Use when a user can't sign
  in, or a connected server stopped working after its credentials changed.
---

# Triage: sign-in and authorization

First separate **two different logins**. Mixing them up is the most common
reason a fix doesn't work.

| Login | What it is | Fails as | Fixed by |
| --- | --- | --- | --- |
| **Client → Willow** | The AI client proves who the user is to the Willow gateway (browser OAuth) | `Unauthorized`, `401`, "no tools", Authorize never completes | Sign in again (Section A) |
| **Willow → a server** (GitHub, Jira, ...) | The user's own connection to one integration | That one server fails or shows not connected; others work | Connect / Re-authenticate that server (Section B) |

If every server fails the same way, it's Client → Willow. If one fails, it's
Willow → that server.

Never print tokens while diagnosing: don't dump client config or token files,
and with the CLI don't run `willow auth token` or read `auth.json`.

## Section A — Client → Willow

### A1. What is the client really doing?

A `401` is **not itself the failure**. It is the first answer every HTTP MCP
client gets, and it carries the pointer to the sign-in service. The question is
whether the client then completes sign-in. Sign-in has four moving parts:

1. the gateway answers `401` with a challenge;
2. the client fetches the sign-in metadata (`/.well-known/oauth-*`);
3. a browser opens the Authorize page and the user clicks **Authorize**;
4. the browser returns to the client (a `localhost` redirect for many clients),
   and the client stores the token.

Run the `triage-willow` evidence script. Its endpoint probe tells you whether
steps 1 and 2 work from this machine:

| Probe | Meaning |
| --- | --- |
| `401` + challenge, both discovery URLs `200` | The network side is fine. The problem is in steps 3 or 4: the browser or the client. |
| Discovery URLs not `200`, or `000` / TLS errors | A proxy, firewall, VPN or certificate setup is blocking sign-in. Escalate to IT or the Willow admin with the probe output. |
| `200` + web page, or `404` | The URL is wrong, so sign-in never starts. `triage-willow-client-setup`. |

Also check the client's own status for Willow (Claude Code `/mcp`; Cursor
**Settings → Tools & MCP**; VS Code **MCP: List Servers**). Needs
authentication → continue below.

CLI users also have `willow auth status` (0 = signed in, 4 = must log in) and
`willow auth whoami` (identity, org, context).

### A1b. Did the browser show a Willow error page?

If sign-in ended on a page with a title like **Account Not Found**, **AI Tool
Disabled**, **Client Not Approved**, **Authorization Denied** or **Sign-In
Expired**, that title is the diagnosis. Look it up in
[references/sign-in-errors.md](references/sign-in-errors.md). Most of these
need the admin or IT, and re-trying the same sign-in won't change them. Copy the
details shown on the page into the report.

Using the universal URL `https://mcp.withwillow.ai/mcp`? There the org is typed
at sign-in, not in the URL. "We couldn't find that organization" means a wrong
identifier, and "isn't reachable through the universal endpoint" means the org
has its own gateway, so use the **Connect MCP** URL instead. The same reference
covers both.

### A2. Fix

| Symptom | Fix |
| --- | --- |
| `401` / `Unauthorized`, or the Authorize page was closed unclicked | **Disconnect and reconnect from scratch.** In **Connect MCP**, copy a *fresh* URL, add it to the client again, and click **Authorize** when the browser opens. |
| Browser shows a **404 on `localhost`** after you finish signing in | The redirect back to the client was missed. Return to the client, trigger authentication again (restart the session or re-run the MCP setup), retry. It usually succeeds on the 1st or 2nd retry. |
| Authorize page never opens | Reconnect from the client (Claude Code: `/mcp` → `willow` → **Reconnect**; Cursor: switch Willow off and on). If the probe was clean, check that the browser isn't blocking the window. |
| Authorize page loops or never returns | Fully quit the client, reopen it, start the connection again once. Don't click Authorize repeatedly in several tabs. |
| Signed in as the wrong person or org | Disconnect the entry and reconnect, choosing the right account in the browser. Organizations are separate under one login; the org is the host in the URL, and the profile menu in Willow switches orgs. |
| Works, then needs sign-in again | The stored sign-in expired or was revoked. Reconnect the same way. Frequent repeats are worth escalating with the evidence output. |
| `403` `Access denied: your IP address (...) is not permitted by this organization's IP access filter` | The org only allows certain networks. Connect from the office network or VPN, or ask the admin to update the filter. Signing in again won't help. |
| Only one AI client can't sign in, others can | That client is disabled for the org (**AI Tool Disabled**), or only allowed with admin-issued credentials (**Client Not Approved**). Use an allowed client, or ask the admin. |
| CLI exit 4 | `willow auth login` in the foreground. Needs a browser; it can't be done from a headless daemon. |
| CLI works, then fails after days | Expired token the background daemon can't refresh. `willow auth login`, then see `diagnose-willow` if timeouts follow. |

Reconnecting changes the user's setup: say what you will remove and re-add.
With the CLI, `willow auth logout` removes the stored sign-in, so ask first.

### A3. Things that are not fixable here

- **Email or password changes.** Willow uses the organization's SSO (Google,
  Microsoft, Okta, ...). Changes happen in the company identity system.
- **SSO sign-in errors on the identity provider's own page.** Send the user to
  their IT or Willow admin with the exact message.
- **"New invite but I already have an account."** Likely a different
  organization; accept it and switch orgs from the profile menu.

## Section B — Willow → one server

### B1. Connecting

1. **Connect** on the server's card starts OAuth in a **popup window**.
2. If nothing opens, the browser blocked it: allow popups for the Willow site
   and click **Connect** again.
3. Some servers return automatically; others show a consent screen you must
   approve.
4. The status dot turns green and the button becomes **Use**.

### B2. The server worked and now doesn't

Use the card's **⋮** menu:

| Action | Use it when |
| --- | --- |
| **Re-authenticate** | Authorization expired or was revoked. It refreshes using the server's *existing* method. |
| **Disconnect**, then **Connect** | The admin changed the server's authentication method. Existing connections keep the old method and **Re-authenticate reuses it**, so it won't switch. |
| **Enable** | The card shows **Enable** instead of **Disable**: the server is off. |

These change the user's connection, so confirm before doing them on their
behalf. They are done in the Willow portal, not from here.

A failing tool call often says this itself, with a link: `Sign in to <server>
to use this tool ... <url>`, `Failed to generate access token for <server>.
Please reauthorize at: <url>`, or `Your single sign-on session for <server> has
expired ... <url>`. Show the user that link; it goes to the right place. Two
messages mean signing in **won't** help: `... missing OAuth scope ... A Willow
admin needs to reconnect ...` and `... no sign-in can fix it ...`. Both go to the
admin.

A **Nothing to Connect** page after **Connect** means the server needs no
separate sign-in: it uses the Willow sign-in, or none. If its tools still fail,
look elsewhere (`triage-willow-tool-failures`).

### B3. Confirm with the Willow MCP

If the Willow MCP is available (search the client's tool list for `connect` or
`status`, read the schema first, read-only calls only), check whether the
server shows as connected for this user. A server that's connected in Willow but failing upstream is an
upstream-side problem: escalate with the exact error and the time.

## Verify and escalate

Verified means: the client shows Willow as connected and lists tools (CLI:
`willow auth status` exits 0) *and* a trivial read-only tool call on the
affected server succeeds.

If not, use the `triage-willow` evidence script and report, and state which
Section (A or B) failed and with what exact error text.
