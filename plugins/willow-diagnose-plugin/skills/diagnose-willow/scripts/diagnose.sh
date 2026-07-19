#!/usr/bin/env bash
#
# Diagnose and fix willow CLI failures (including "Daemon request timeout").
# Safe to re-run: it only kills the willow daemon and clears its socket dir.

set -u

CLI="${WILLOW_BIN:-willow}"
SOCK_DIR="/tmp/willow-$(id -u)"
PID_FILE="$SOCK_DIR/willow.pid"

hr() { printf '%s\n' "------------------------------------------------------------"; }
say() { printf '\n== %s\n' "$1"; }

if ! command -v "$CLI" >/dev/null 2>&1; then
  echo "ERROR: '$CLI' not found on PATH. Set WILLOW_BIN or install willow."
  exit 1
fi

say "0. Built-in diagnostics (willow doctor)"
hr
"$CLI" doctor || true
hr

say "1. Current daemon / socket state"
if [ -d "$SOCK_DIR" ]; then
  ls -la "$SOCK_DIR" || true
else
  echo "No socket dir at $SOCK_DIR (no daemon has run, or already clean)."
fi

say "2. Killing stale daemon and clearing sockets"
# willow has no kill-daemon command: kill the pid, then remove the socket dir.
if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null; then
    echo "Killed daemon pid $pid."
  fi
fi
rm -rf "$SOCK_DIR" 2>/dev/null || true
echo "Done."

say "3. Checking auth (exit 4 = must re-login)"
if "$CLI" auth status; then
  echo "Auth OK."
else
  code=$?
  if [ "$code" -eq 4 ]; then
    echo ">> Not logged in / token expired. Run: $CLI auth login"
  else
    echo ">> auth status exited with code $code."
  fi
fi

say "4. Retrying tool listing WITH the daemon"
hr
if WILLOW_DEBUG=1 "$CLI" tools grep test 2>/tmp/willow-diag-daemon.log; then
  hr
  echo "SUCCESS: listing works again with the daemon. You're good."
  echo "Debug log: /tmp/willow-diag-daemon.log"
  exit 0
fi
hr
echo "Still failing with the daemon. Debug log: /tmp/willow-diag-daemon.log"
tail -n 20 /tmp/willow-diag-daemon.log 2>/dev/null || true

say "5. Retrying WITHOUT the daemon (direct connection)"
"$CLI" config set settings.daemon false >/dev/null 2>&1 || true
hr
if WILLOW_DEBUG=1 "$CLI" tools grep test 2>/tmp/willow-diag-direct.log; then
  hr
  echo "SUCCESS with daemon disabled -> the daemon layer was the problem."
  echo "Leave it disabled, or re-enable later with:"
  echo "    $CLI config set settings.daemon true"
  echo "Debug log: /tmp/willow-diag-direct.log"
  exit 0
fi
hr
echo "Still failing even without the daemon -> the bottleneck is the gateway,"
echo "network, or auth (NOT the local daemon)."
echo "Debug log: /tmp/willow-diag-direct.log"
tail -n 20 /tmp/willow-diag-direct.log 2>/dev/null || true
echo
echo "Next: verify gateway reachability (replace <org>):"
echo "    curl -sS -o /dev/null -w \"%{http_code} %{time_total}s\\n\" https://<org>.mcp-s.com/mcp"
echo "Then send both debug logs above to support."
exit 2
