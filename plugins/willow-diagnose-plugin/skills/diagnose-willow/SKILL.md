---
name: diagnose-willow
description: >-
  Diagnose and fix willow CLI failures — including "Daemon request timeout"
  ("Warning: Failed to connect to server: Daemon request timeout" and
  "<error: Daemon request timeout>" when listing or grepping tools), auth
  failures, gateway reachability, an unsupported Node.js version, and a
  stale/cached CLI build (an old version kept alive by the npx cache). Use when
  willow commands time out, tools fail to list, the CLI reports an old version
  or refuses to run on your Node, or MCP calls hang from an agent such as Codex,
  Claude, or Cursor.
---

# Troubleshoot the willow CLI

Most "willow is broken" reports fall into a few buckets: a bad **environment**
(unsupported Node.js version or a stale/cached CLI build), a stale local
**daemon**, **expired auth**, or a slow/unreachable **gateway**. Start with the
built-in `willow doctor` — it inspects Node, config, auth, daemon, and gateway at
once — then follow the fix workflow.

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
5. **Unsupported Node.js version.** willow requires **Node >= 18**. On older
   Node the CLI can crash with syntax errors, `fetch is not defined`, or exit
   before it ever reaches the gateway. Fix: install/switch to Node >= 18.
6. **Stale / cached CLI build.** Agents usually launch willow through
   `npx @willowai/cli`, and npx caches the package — so it can keep running an
   old version even after a global update, missing bug fixes for the errors
   above. Fix: update the CLI and clear the npx cache.

Causes 5 and 6 are **environment** problems: they happen before (or independent
of) any daemon/auth/gateway logic, so check them first when the version looks
old or the CLI won't even start. See "Environment: Node & CLI version" below.

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
its output to jump straight to the failing area below. If `willow doctor` flags
the **node** row or you suspect an old build (or `willow` won't start at all),
do "Step 0.5 — Environment" before anything else.

**Step 0.5 — Environment: Node & CLI version:**

Node must be **>= 18**. Check it, and check whether you're running the latest
CLI build:

```bash
node -v                          # must be >= v18
willow --version                 # installed CLI version
npm view @willowai/cli version   # latest published version
```

Fix an old Node (use whatever version manager you have):

```bash
nvm install 20 && nvm use 20     # nvm
# or: fnm use 20 / volta install node@20 / brew upgrade node
```

Fix an old CLI build — self-update, then clear the npx cache so agents that
launch `npx @willowai/cli` stop reusing the stale copy:

```bash
willow update                    # self-update the global @willowai/cli
npx clear-npx-cache              # drop cached npx package versions
# fallback if the above isn't available:
rm -rf "$(npm config get cache)/_npx"
```

If a wrapper/agent invokes the CLI via npx, pin it to the latest to bypass the
cache entirely: `npx @willowai/cli@latest ...`. After fixing the environment,
re-run `willow doctor` and continue below only if problems remain.

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
- Output of `willow doctor`, `willow --version`, and `node -v`.
- Whether the CLI is launched directly or via `npx @willowai/cli`, and whether
  clearing the npx cache changed anything.

## Quick reference

| Command                                        | Purpose                                   |
| ---------------------------------------------- | ----------------------------------------- |
| `willow doctor`                                | Diagnose env, config, auth, daemon, MCP   |
| `node -v`                                       | Check Node version (must be >= 18)        |
| `willow --version`                              | Show installed CLI version                |
| `npm view @willowai/cli version`               | Show latest published CLI version         |
| `willow update`                                | Self-update to the latest CLI             |
| `npx clear-npx-cache`                           | Clear stale npx-cached CLI builds         |
| `npx @willowai/cli@latest ...`                  | Run the latest CLI, bypassing npx cache   |
| `kill "$(cat /tmp/willow-$(id -u)/willow.pid)"`| Stop the background daemon                |
| `rm -rf "/tmp/willow-$(id -u)/"`               | Clear leftover socket/PID files           |
| `willow auth status`                           | Check login state (exit 4 = re-login)     |
| `willow auth login`                            | Re-authenticate in the foreground         |
| `willow config set settings.daemon false`      | Disable daemon (direct connect)           |
| `WILLOW_DEBUG=1 willow ...`                     | Verbose debug output to stderr            |
