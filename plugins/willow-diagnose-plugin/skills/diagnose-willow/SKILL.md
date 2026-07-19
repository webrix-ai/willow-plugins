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

Most "willow is broken" reports fall into three buckets: a stale local **daemon**,
**expired auth**, or a slow/unreachable **gateway**. Start with the built-in
`willow doctor` — it inspects all three at once — then follow the fix workflow.

`Daemon request timeout` in particular is a **client-side** error. It is raised
by willow when its background daemon does not answer an IPC request in time — it
is NOT an error sent by any MCP server or tool. That is why it looks "not
tool/server specific": it fails the same way for every server.

## How the daemon works (why this happens)

willow keeps a long-lived, detached **daemon** process that holds the MCP
connection so repeated invocations are fast. The daemon is **reused** as long as
its PID is alive, the config hash matches, and its socket file exists. It does
**not** detect when its upstream MCP connection has silently died (gateway
restart, network blip, expired token). So a daemon can stay "alive but broken"
and every call routed to it times out — which is why the problem persists across
retries.

Daemon files live in `/tmp/willow-$(id -u)/`:

| File           | Purpose                          |
| -------------- | -------------------------------- |
| `willow.sock`  | IPC socket the CLI connects to   |
| `willow.pid`   | PID of the running daemon        |
| `willow.ready` | readiness marker                 |

> **Note:** willow has no `kill-daemon` command. To clear a stale daemon, kill
> the PID in `willow.pid` and remove the socket dir (the next invocation starts
> a fresh daemon). You can also just disable the daemon with
> `willow config set settings.daemon false`.

## Most common causes

1. **Stale / broken daemon reused across runs** (most common when it persists
   for days). Fix: kill the daemon PID and clear its socket dir.
2. **Expired auth.** The daemon runs without an interactive browser, so it
   cannot refresh tokens. Fix: re-login in the foreground.
3. **Slow gateway tool enumeration.** Listing aggregates every integration in
   the org; if one upstream integration hangs, the whole list is slow.
4. **Network path to the gateway** (VPN / proxy / DNS) is blocked or slow.

## Fix workflow

Run the automated diagnostic first — it performs the steps below and tells you
what to do next:

```bash
bash scripts/diagnose.sh
```

If you prefer to do it manually, follow this order and stop as soon as tools
list successfully:

**Step 0 — Ask willow to diagnose itself:**

```bash
willow doctor   # checks node, config, contexts, auth, daemon, MCP reachability
```

`willow doctor` prints a checklist and exits non-zero if any check FAILs. Use
its output to jump straight to the failing area below.

**Step 1 — Kill the stale daemon (fixes most cases):**

```bash
# Kill the daemon process (if any) and clear its socket dir
[ -f "/tmp/willow-$(id -u)/willow.pid" ] && kill "$(cat "/tmp/willow-$(id -u)/willow.pid")" 2>/dev/null
rm -rf "/tmp/willow-$(id -u)/"
willow tools grep test   # retry (a fresh daemon starts automatically)
```

**Step 2 — Confirm auth:**

```bash
willow auth status   # exit 0 = OK; exit 4 = must re-login
willow auth login    # only if status returned 4
```

**Step 3 — Isolate daemon vs. gateway by bypassing the daemon:**

```bash
willow config set settings.daemon false
willow tools grep test
```

- Works now → it was the daemon layer. Leave the daemon off, or re-enable it
  with `willow config set settings.daemon true` (a fresh daemon starts on the
  next call).
- Killing the daemon helps but the timeout returns within minutes → the gateway
  is slow to enumerate tools (cause 3). See "Mitigate slow enumeration" below.
- Still times out → the bottleneck is the **gateway/network/auth**, not the
  daemon. Continue to Step 4.

**Mitigate slow enumeration (many integrations in the org):**
Listing enumerates every integration the org exposes. Scoping willow to a single
MCP or toolkit shrinks that list:

```bash
willow config set toolkit <toolkit-name>   # limit to one toolkit
# or
willow config set mcp <mcp-name>           # limit to one MCP server
```

**Step 4 — Capture debug logs and check connectivity (for a support ticket):**

```bash
WILLOW_DEBUG=1 willow tools grep test 2> willow-debug.log
cat willow-debug.log
```

Look for `Connection test failed`, `Tool cache warm-up failed`, or
`Failed to connect`. Then confirm the gateway is reachable (replace `<org>`):

```bash
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" https://<org>.mcp-s.com/mcp
```

## What to send to support if it is still failing

Attach `willow-debug.log` and include:

- Which step(s) changed the behavior (especially the Step 3 result).
- Your org slug and the `curl` status/time from Step 4.
- Output of `willow doctor` and `willow --version`.

## Quick reference

| Command                                        | Purpose                                   |
| ---------------------------------------------- | ----------------------------------------- |
| `willow doctor`                                | Diagnose env, config, auth, daemon, MCP   |
| `kill "$(cat /tmp/willow-$(id -u)/willow.pid)"`| Stop the background daemon                |
| `rm -rf "/tmp/willow-$(id -u)/"`               | Clear leftover socket/PID files           |
| `willow auth status`                           | Check login state (exit 4 = re-login)     |
| `willow auth login`                            | Re-authenticate in the foreground         |
| `willow config set settings.daemon false`      | Disable daemon (direct connect)           |
| `WILLOW_DEBUG=1 willow ...`                     | Verbose debug output to stderr            |
