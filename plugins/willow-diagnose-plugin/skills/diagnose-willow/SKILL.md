---
name: diagnose-willow
description: >-
  Diagnose and fix willow CLI failures — including "Daemon request timeout"
  ("Warning: Failed to connect to server: Daemon request timeout" and
  "<error: Daemon request timeout>" when listing or grepping tools), auth
  failures, and gateway reachability. Use when willow commands time out, tools
  fail to list, or MCP calls hang from an agent such as Codex, Claude, or Cursor.
---

# Troubleshoot the willow CLI

**Scope:** this skill is only for the `willow` command-line tool and its local
daemon. Most people connect an AI client straight to Willow over HTTP MCP, with
no CLI at all. For "no tools", 401, a client that won't connect, or a failing
tool call in that setup, use `triage-willow` instead.

Most "willow is broken" reports fall into four buckets: a stale local **daemon**,
**expired auth**, a slow/unreachable **gateway**, or a local **network/TLS**
setup (proxy, corporate CA, VPN). Start with the built-in `willow doctor` — it
inspects all of them at once — then follow the fix workflow.

`Daemon request timeout` in particular is a **client-side** error. It is raised
by willow when its background daemon does not answer an IPC request in time — it
is NOT an error sent by any MCP server or tool. That is why it looks "not
tool/server specific": it fails the same way for every server.

For problems that are not the CLI itself (no tools in an AI client, 401 in
Cursor, a blocked tool call), use the `triage-willow` skill instead.

## Ground rules

- **Diagnose first, change second.** Reading state is always fine. Stopping the
  daemon, changing `settings.daemon`, logging in or out, and updating the CLI
  change the user's setup: say what each does and get a go-ahead.
- **Never print secrets.** Don't run `willow auth token` and don't read
  `~/.config/willow/auth.json`. Debug logs can contain request details: redact
  them (the bundled script does) and have the user read them before sharing.
- **Ask only what the script can't see**, at most three questions at once:
  the exact command and its output; whether it hangs every time or only after
  a while (sleep, network change, an update); and whether they're on a VPN or
  a corporate network with a proxy.

## How the daemon works (why this happens)

willow keeps a long-lived, detached **daemon** process that holds the MCP
connection and caches the tool catalog so repeated invocations are fast. The
daemon is **reused** as long as its PID is alive, the config hash matches, and
its socket file exists. It does **not** detect when its upstream MCP connection
has silently died (gateway restart, network blip, expired token). So a daemon
can stay "alive but broken" and every call routed to it times out — which is why
the problem persists across retries.

The CLI manages it for you:

| Command | What it does |
| --- | --- |
| `willow daemon status` | Running or not, pid, daemon CLI version vs this CLI, start time. Also reports a **stale pid file** and a **disabled** daemon. |
| `willow daemon refresh` | Stop the daemon and drop its cached catalog. A fresh one starts on the next call. **The usual fix.** |
| `willow daemon stop` | Stop it without respawning in this run. |
| `willow daemon disable` / `enable` | Set `settings.daemon` false/true (disable also stops it). |
| `willow tools refresh` | Same cache-clearing effect, from the tools side. |

Things `daemon status` makes visible:

- **`stale pid file`**: the process is gone but its file remains. Cleaned up on
  the next invocation; if timeouts continue the cause is elsewhere.
- **Daemon version differs from "this cli"**: a daemon left over from before
  `willow update`. `willow daemon refresh` clears it.
- **`disabled`**: a stuck daemon cannot be the cause. Look at auth, gateway or
  network.

Files live in `/tmp/willow-$(id -u)/` (`willow.sock`, `willow.pid`,
`willow.ready`). You should not need to touch them. Only if an older CLI has no
working `willow daemon` command, stop the PID in `willow.pid` and remove that
directory.

## Most common causes

1. **Stale / broken daemon reused across runs** (most common when it persists
   for days). Fix: `willow daemon refresh`.
2. **Expired auth.** The daemon runs without an interactive browser, so it
   cannot refresh tokens. Fix: re-login in the foreground.
3. **Slow gateway tool enumeration.** Listing aggregates every integration in
   the org; if one upstream integration hangs, the whole list is slow.
4. **Network path to the gateway** (VPN / proxy / DNS) is blocked or slow.
5. **Local TLS or Node network setup**, shown by `willow doctor` under
   "Network" and "MCP transport": an `NODE_EXTRA_CA_CERTS` path that doesn't
   exist, a proxy or corporate CA, or IPv4/IPv6 auto-select problems on a VPN
   (mostly Node 24+).

## Fix workflow

Run the diagnostic first. By default it is **read-only**: it prints doctor
output, daemon and auth state, tries one tool listing, and tells you what to do
next.

```bash
bash scripts/diagnose.sh
```

If listing fails and auth is fine, and the user agrees to the changes below:

```bash
bash scripts/diagnose.sh --fix
```

`--fix` resets the daemon (`willow daemon refresh`) and retries. If that isn't
enough it turns the daemon off briefly to test the direct path, **then puts the
setting back**. Add `--disable-daemon` only if the user wants the daemon left
off when that is what makes listing work.

Doing it by hand, in this order, and stopping as soon as tools list:

**Step 0 — Ask willow to diagnose itself (read-only):**

```bash
willow doctor   # node, config, contexts, auth, daemon, network/TLS, MCP reachability
```

It exits non-zero if any check FAILs. Use the output to jump to the failing
area below.

**Step 1 — Look at the daemon, then reset it (fixes most cases):**

```bash
willow daemon status    # read-only
willow daemon refresh   # changes state: ask first
willow tools grep test  # retry (a fresh daemon starts automatically)
```

**Step 2 — Confirm auth:**

```bash
willow auth status   # exit 0 = OK; exit 4 = must re-login
willow auth login    # only if status returned 4; opens a browser
```

`auth status` is an offline check of the stored token. A call can still succeed
if the token is refreshable, so treat exit 4 as the likely cause only when a
call actually fails.

**Step 3 — Isolate daemon vs. gateway by bypassing the daemon:**

```bash
willow daemon disable
willow tools grep test
willow daemon enable      # put it back unless you are leaving it off on purpose
```

- Works with the daemon off → it was the daemon layer. Leave it off, or
  re-enable it (`willow daemon enable`; a fresh daemon starts on the next call).
- Resetting the daemon helps but the timeout returns within minutes → the
  gateway is slow to enumerate tools (cause 3). See "Mitigate slow enumeration".
- Still times out → the bottleneck is the **gateway/network/auth**, not the
  daemon. Continue to Step 4.

**Mitigate slow enumeration (many integrations in the org):**
Listing enumerates every integration the org exposes. Scoping willow to a single
MCP or toolkit shrinks that list:

```bash
willow context add <name> --mcp <mcp-name> --use    # or --toolkit <toolkit-name>
willow context list                                 # active context is starred
```

(Older CLIs: `willow config set mcp <mcp-name>` / `toolkit <toolkit-name>`.)
This narrows what the user sees, so tell them which context is now active and
how to go back (`willow context use default`).

**Step 4 — Capture debug logs and check connectivity (for a support ticket):**

```bash
WILLOW_DEBUG=1 willow tools grep test 2> willow-debug.log
```

Look for `Connection test failed`, `Tool cache warm-up failed`, or
`Failed to connect`. Redact before sharing (tokens, emails). Then probe the
gateway **at the URL the CLI is really using** (shown by `willow config show`
as `baseUrl`, or derived from `org`); it is not always `*.mcp-s.com`:

```bash
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" <gateway-url>
```

`401` means reachable and asking for a token (good). `000` or a timeout means
network, VPN, proxy, DNS or TLS.

**Step 5 — Network/TLS findings from `willow doctor`:**

- `extra CA certs ... path does not exist`: fix or unset `NODE_EXTRA_CA_CERTS`;
  a missing corporate cert chain can fail TLS on Node 24+.
- TCP and TLS pass but the MCP handshake fails on Node 24+: test with
  `NODE_OPTIONS=--no-network-family-autoselection willow tools grep test`.
- Proxy variables set: confirm the proxy allows the gateway host.

**Old CLI?** `willow update --check` says whether a newer version exists;
`willow update` installs it (ask first). Several fixes above need a current CLI.

## What to send to support if it is still failing

Attach the redacted debug log and include:

- Which step(s) changed the behavior (especially the Step 3 result).
- Your org slug and the `curl` status/time from Step 4.
- Output of `willow doctor` and `willow --version`.

If the `triage-willow` skill is installed, its evidence script collects all of
this with secrets redacted.

## Quick reference

| Command | Purpose | Changes state? |
| --- | --- | --- |
| `willow doctor` | Diagnose env, config, auth, daemon, network, MCP | No |
| `willow daemon status` | Daemon pid, version, stale/disabled state | No |
| `willow auth status` | Login state (exit 4 = re-login) | No |
| `willow daemon refresh` | Stop daemon and clear its catalog cache | Yes |
| `willow tools refresh` | Clear the cached tool catalog | Yes |
| `willow daemon disable` / `enable` | Turn the daemon off / on | Yes |
| `willow auth login` | Re-authenticate in the foreground | Yes |
| `WILLOW_DEBUG=1 willow ...` | Verbose debug output to stderr | No |
