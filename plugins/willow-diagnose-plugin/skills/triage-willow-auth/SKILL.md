---
name: triage-willow-auth
description: >-
  Fix Willow sign-in and authorization problems: "Unauthorized" or 401, the
  Authorize step never completing, a 404 on localhost after signing in, a
  blocked OAuth popup on Connect, `willow auth status` exit code 4, a server
  stuck on an old auth method, or Re-authenticate not helping. Use when a user
  can't sign in, keeps getting logged out, or a connected server stopped
  working after its credentials changed.
---

# Triage: sign-in and authorization

First separate **two different logins**. Mixing them up is the most common
reason a fix doesn't work.

| Login | What it is | Fails as | Fixed by |
| --- | --- | --- | --- |
| **Client → Willow** | The AI client or CLI proves who the user is to the Willow gateway | `Unauthorized`, `401`, "no tools", `willow auth status` exit 4 | Sign in again (Section A) |
| **Willow → a server** (GitHub, Jira, ...) | The user's own connection to one integration | That one server fails or shows not connected; others work | Connect / Re-authenticate that server (Section B) |

If every server fails the same way, it's Client → Willow. If one fails, it's
Willow → that server.

Never print tokens while diagnosing: no `willow auth token`, no reading
`auth.json`.

## Section A — Client → Willow

### A1. What does the state say?

```bash
willow auth status      # exit 0 = signed in, 4 = must log in
willow auth whoami      # identity, org and context currently in use
```

`whoami` showing an unexpected org or context explains "I'm signed in but see
nothing". Say so and fix the context rather than re-logging in.

### A2. Fix

| Symptom | Fix |
| --- | --- |
| `401` / `Unauthorized`, or the Authorize page was closed unclicked | **Disconnect and reconnect from scratch.** In **Connect MCP**, copy a *fresh* URL, add it to the client again, and click **Authorize** when the browser opens. |
| CLI exit 4 | `willow auth login` in the foreground. Needs a browser; it can't be done from a headless daemon. |
| Browser shows a **404 on `localhost`** after you finish signing in | The redirect back to the client was missed. Return to the client, trigger authentication again (restart the session or re-run the MCP setup), retry. It usually succeeds on the 1st or 2nd retry. |
| Authorize page loops or never returns | Fully quit the client, reopen it, start the connection again once. Don't click Authorize repeatedly in several tabs. |
| Signed in as the wrong person or org | `willow auth logout` then `willow auth login`, or pick the right org from the profile menu. Organizations are separate under one login. |
| Works, then fails after days (CLI) | Expired token the background daemon can't refresh. `willow auth login`, then see `diagnose-willow` if timeouts follow. |

Ask before running `willow auth logout`; it removes the stored sign-in.

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

### B3. Confirm with the Willow MCP

If the Willow MCP is available (`willow tools grep connect` to find it, and
read-only calls only), check whether the server shows as connected for this
user. A server that's connected in Willow but failing upstream is an
upstream-side problem: escalate with the exact error and the time.

## Verify and escalate

Verified means: `willow auth status` exits 0 (or the client lists tools) *and*
a trivial read-only tool call on the affected server succeeds.

If not, use the `triage-willow` evidence script and report, and state which
Section (A or B) failed and with what exact error text.
