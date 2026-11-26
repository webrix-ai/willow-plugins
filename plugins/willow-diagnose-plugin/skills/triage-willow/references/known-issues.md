# Known Willow issues — symptom to fix

Source of truth: Willow's end-user docs (Troubleshooting, FAQ, Refresh Your
Tools, MCP Servers, Willow CLI). Keep this file in step with those pages.

| Symptom | Likely cause | First check | Fix |
| --- | --- | --- | --- |
| Client says "no tools available" | Authorization never completed; server disabled; client not restarted; wrong URL | Did the browser Authorize page get a click? Is the server showing **Enable** instead of **Disable**? | Re-connect and click Authorize; enable the server; fully restart the client; compare the client URL with the one in **Connect MCP** |
| `Unauthorized` / `401` | Session expired or authorization never completed | `willow auth status` (4 = not signed in) | Disconnect and reconnect from scratch with a fresh URL from **Connect MCP**; CLI: `willow auth login` |
| Browser shows 404 on `localhost` right after signing in | Redirect back to the client was missed | — | Go back to the client, trigger re-authentication, retry. Usually works within 1–2 attempts |
| Popup never appears on **Connect** | Browser blocked the popup | Address bar popup indicator | Allow popups for the Willow site, click **Connect** again |
| Client "connects" but gets a web page / no MCP response | URL is the Willow portal: `/mcp` is missing (endpoint probe: `200` + HTML) | Evidence script endpoint probe | Use `https://<host>/mcp` from **Connect MCP** |
| Probe returns `404` on POST | Typo in the path (`/mcpp`, wrong segment) | Endpoint probe | Fix the path to match **Connect MCP** |
| `http://` URL fails or loops | The gateway redirects `http://` to `https://`; a client may drop the POST on the redirect | Endpoint probe shows `301` | Use the `https://` URL directly |
| `401` in a client log, but sign-in does start | Normal: the first answer every client gets, which points it at sign-in | Client then opens the browser | Nothing to fix; complete **Authorize** |
| "Authorize never completes" and nothing opens, other clients on another network work | A proxy, firewall, VPN or TLS inspection blocks `/.well-known/oauth-*`, `/authorize`, `/token` or `/register` | Evidence script: discovery URLs not `200`, or TLS errors | Ask IT to allow the Willow host; test on another network |
| Wrong org or server name in the URL | Both still answer `401` before sign-in, so the typo only shows after Authorize | Compare host and names with **Connect MCP** | Copy the URL from **Connect MCP** again |
| Connection refused / can't reach server | Network, `http://` instead of `https://`, gateway domain not deployed | Gateway probe in the evidence output | Fix connectivity, use `https://`, ask the admin to confirm the domain is active |
| Cursor ignores the Willow entry | Missing `"type": "http"` in `~/.cursor/mcp.json` | Open the file | Add `"type": "http"`, restart Cursor |
| Claude Code shows Willow `disconnected` | Connection dropped or never added | `/mcp` inside Claude Code | `claude mcp add --transport http willow https://<org>.withwillow.ai/mcp` |
| Tool names or `account` choices are out of date; `Unknown account "<name>"` | The client is using the tool list it fetched when it connected, before an API key was added, removed or renamed | Compare the tool's parameters with the **API keys** dialog | Refresh the client's tool list (new session, or restart); CLI: `willow tools refresh` |
| CLI TLS or MCP handshake fails on Node 24+ while `tcp`/`tls` checks pass | `NODE_EXTRA_CA_CERTS` points at a missing file, a proxy or corporate CA, or IPv4/IPv6 auto-select on a VPN | `willow doctor` "Network" and "MCP transport" sections | Fix or unset the CA path; to test, `NODE_OPTIONS=--no-network-family-autoselection willow tools grep test` |
| Only one server's tools show | URL has a scope (`?mcp=`, `?toolkit=`, `/mcp/mcp/<server>`, `/mcp/toolkit/<name>`); or a CLI context is scoped | Client URL; `willow context list` | Use the unscoped URL, or switch context with `willow context use` |
| Server missing from the list | Not granted to this user | Admin sees it, user does not | Ask the admin for access |
| Connection still uses an old auth method after the admin changed it | **Re-authenticate** reuses the old method | — | **Disconnect**, then **Connect** again |
| Calls to a server fail right after it was disabled or disconnected | Tools vanish immediately when the server is off | Server card state | Re-enable the server |
| A request is held on a human-approval popup | A guard needs approval | The popup in the client or browser | Choose allow once, always allow, or deny; if it never appears, see `triage-willow-tool-failures` |
| `Daemon request timeout` (CLI) | Stale or stuck local daemon | `willow doctor` | `diagnose-willow` |

## Not bugs

- **Can't change email or password in Willow.** Willow uses the organization's
  SSO. Use the company identity provider.
- **A new invite when an account already exists.** Probably another
  organization. Accept it and switch orgs from the profile menu.
- **Skills and commands a user created are private to them.** Only admin
  publishing makes them org-wide.
