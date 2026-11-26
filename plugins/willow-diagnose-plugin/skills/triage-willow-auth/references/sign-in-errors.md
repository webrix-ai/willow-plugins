# Willow sign-in and connect errors

## Pages the browser shows

When sign-in to Willow, or **Connect** on a server, fails, the browser lands on
a Willow error page with one of these titles. The page may also show details
from the identity provider: copy them exactly.

| Page title | What it means | What to do |
| --- | --- | --- |
| **Account Not Found** | This person isn't a user in that Willow organization, or the link was for a different org | Start the connection again from Willow or the client. Still failing: the admin must add the user, or the user picked the wrong org. |
| **Authorization Denied** | The company identity provider refused: the account isn't assigned to the app, or an access policy denied it | IT / the admin assigns the user to the app. Send them the details shown on the page. |
| **AI Tool Disabled** | The admin disabled this AI client for the organization | Use an allowed client, or ask the admin to enable it (Willow **AI Tools**) |
| **Client Not Approved** | The admin only lets this AI client connect with credentials they issued; automatic registration is off for it | Ask the admin for the configuration they issued for this client |
| **Organization Inactive** | The organization is deactivated | Admin / Willow support |
| **SAML Not Configured** | The org has no SAML sign-in set up | Admin checks SSO settings |
| **Sign-In Rejected** | Willow couldn't verify the identity provider's SAML response | Admin checks the SAML settings match the IdP app |
| **Sign-In Expired** | The sign-in took too long, or started outside Willow | Open Willow, or the client, and sign in again |
| **Redirect URI Mismatch** / **Invalid Client** | The client's registration doesn't match | Remove the Willow entry from the client and add it again so it registers fresh |
| **OAuth Discovery Failed** | Willow couldn't reach the server's own sign-in service | Retry once; if it repeats, admin / Willow support |
| **Authentication Failed** / **Empty Credentials** | The server's provider didn't complete the code exchange | Retry Connect once; then admin, with the details |
| **Nothing to Connect** | This server needs no separate sign-in: it uses the Willow sign-in, or none at all | Nothing to do. If its tools still fail, it isn't an auth problem. |
| **Configuration Error** / **Credentials Mapping Failed** / **Integration Not Found** / **Connector Not Found** / **Installation Failed** / **Credentials Save Failed** | The server is misconfigured in Willow | Admin |
| **Missing Parameters** / **Invalid Signature** | The sign-in link was broken or altered | Start again from the client, not from an old link |

## Universal URL (`https://mcp.withwillow.ai/mcp`)

The org isn't in this URL; the user picks it when signing in. EU orgs use
`https://mcp.eu.withwillow.ai/mcp`.

| Message | Meaning | What to do |
| --- | --- | --- |
| **"We couldn't find that organization"** | The org identifier typed at sign-in is wrong | Use the first part of the gateway host: `acme` in `acme.withwillow.ai` |
| **"That organization isn't reachable through the universal endpoint"** | The org runs its own gateway (self-hosted or custom domain) | Use the URL from **Connect MCP** instead |
| Sign-up didn't return to the client | The email was verified in another browser, or over an hour later | Start the connection again from the client |
| Signed in, but to the wrong org | Willow remembers the last org picked | Disconnect, reconnect, and type the right org |

## Gateway answers (HTTP)

| Answer | Meaning | What to do |
| --- | --- | --- |
| `401` with `WWW-Authenticate: Bearer ... resource_metadata="..."` | Normal before sign-in: the client should open the browser | Nothing, unless sign-in never starts (proxy, client, browser) |
| `401` `invalid_token` after signing in | The stored token is expired or revoked | Reconnect from the client |
| `403` `Access denied: your IP address (<ip>) is not permitted by this organization's IP access filter` | The org only allows certain networks | Connect from the office network or VPN, or the admin updates the IP filter |
