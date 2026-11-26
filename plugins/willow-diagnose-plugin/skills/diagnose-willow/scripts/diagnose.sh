#!/usr/bin/env bash
#
# Diagnose willow CLI failures (including "Daemon request timeout").
#
# Default mode is READ-ONLY: it reports doctor output, daemon and auth state,
# and tries one tool listing as the daemon currently stands (which, like any
# willow command, starts the daemon on demand if it is not running). Nothing is
# stopped, edited or removed.
#
#   bash diagnose.sh                      diagnose only
#   bash diagnose.sh --fix                also reset the daemon and, if that is
#                                         not enough, test with the daemon off
#                                         (the daemon setting is put back)
#   bash diagnose.sh --fix --disable-daemon
#                                         same, but leave the daemon disabled if
#                                         that is what makes listing work
#
# Run --fix only after the user agrees: it stops the background daemon and
# briefly changes `settings.daemon` in the willow config.
#
# Debug logs are redacted (bearer tokens, JWTs, emails, secret-looking values),
# but read them before sharing.

set -u

CLI="${WILLOW_BIN:-willow}"
CONFIG_PATH="${WILLOW_CONFIG_PATH:-$HOME/.config/willow/config.json}"
SOCK_DIR="/tmp/willow-$(id -u)"
PID_FILE="$SOCK_DIR/willow.pid"

FIX=0
KEEP_DISABLED=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --disable-daemon) KEEP_DISABLED=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)"; exit 1 ;;
  esac
done
if [ "$KEEP_DISABLED" -eq 1 ] && [ "$FIX" -eq 0 ]; then
  echo "--disable-daemon only makes sense together with --fix."
  exit 1
fi

hr() { printf '%s\n' "------------------------------------------------------------"; }
say() { printf '\n== %s\n' "$1"; }

redact() {
  sed -E \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+\/=-]+/Bearer [REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/[REDACTED_JWT]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/[A-Za-z0-9._+-]+%40[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/("?([Aa]ccess_?[Tt]oken|[Rr]efresh_?[Tt]oken|[Tt]oken|[Ss]ecret|[Aa]pi_?[Kk]ey|[Aa]uthorization|[Pp]assword|userAccessKey)"?[[:space:]]*[:=][[:space:]]*)"?[^",[:space:]}]+"?/\1"[REDACTED]"/g'
}

if ! command -v "$CLI" >/dev/null 2>&1; then
  echo "ERROR: '$CLI' not found on PATH. Set WILLOW_BIN or install willow (npm install -g @willowai/cli)."
  exit 1
fi

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/willow-diag.XXXXXX")"

# Try one tool listing with debug output; log is redacted into $LOG_DIR/$1.log.
try_listing() {
  local name="$1" log="$LOG_DIR/$1.log"
  WILLOW_DEBUG=1 "$CLI" tools grep test >/dev/null 2>"$log.raw"
  local code=$?
  redact <"$log.raw" >"$log"
  rm -f "$log.raw"
  return "$code"
}

show_log_tail() {
  local log="$LOG_DIR/$1.log"
  echo "Redacted debug log: $log"
  tail -n 20 "$log" 2>/dev/null || true
}

say "0. Built-in diagnostics (willow doctor)"
hr
"$CLI" --version 2>&1 | redact
"$CLI" doctor 2>&1 | redact
hr

say "1. Daemon state"
"$CLI" daemon status 2>&1 | redact
DAEMON_STATUS="$("$CLI" daemon status 2>&1)"
case "$DAEMON_STATUS" in
  *"stale pid"*)
    echo ">> Stale daemon pid file: the process is gone but the file remains." ;;
  *"disabled"*)
    echo ">> The daemon is disabled; a stuck daemon cannot be the cause." ;;
esac
if printf '%s' "$DAEMON_STATUS" | grep -q "version:"; then
  d_ver="$(printf '%s' "$DAEMON_STATUS" | sed -n 's/.*version: *\([^ ]*\) (this cli: \(.*\))/\1 \2/p')"
  set -- $d_ver
  if [ "${1:-}" != "${2:-}" ] && [ -n "${1:-}" ]; then
    echo ">> The running daemon is on CLI version $1 but this CLI is $2 (left over from before an update)."
  fi
fi

say "2. Auth (exit 0 = signed in, 4 = must re-login)"
"$CLI" auth status 2>&1 | redact
AUTH_CODE=${PIPESTATUS[0]}
if [ "$AUTH_CODE" -eq 0 ]; then
  echo "Auth OK."
elif [ "$AUTH_CODE" -eq 4 ]; then
  echo ">> auth status (an offline check) says not logged in or token expired."
  echo "   If the listing below fails, run in the foreground: $CLI auth login"
else
  echo ">> auth status exited with code $AUTH_CODE."
fi

say "3. Tool listing as things stand (read-only)"
hr
if try_listing current; then
  hr
  echo "SUCCESS: listing works. No daemon change was needed."
  echo "If the problem was intermittent, re-run when it happens or use: bash diagnose.sh --fix"
  rm -rf "$LOG_DIR"
  exit 0
fi
hr
echo "Listing FAILED."
show_log_tail current

if [ "$AUTH_CODE" -eq 4 ]; then
  echo
  echo "Auth status reports expired, the most likely cause. Run '$CLI auth login' first,"
  echo "then re-run this script. (The daemon cannot refresh tokens without a browser.)"
  exit 2
fi

if [ "$FIX" -eq 0 ]; then
  echo
  echo "Nothing was changed. Next, with the user's OK:"
  echo "    bash diagnose.sh --fix        # reset the daemon, then test with it off"
  exit 2
fi

say "4. Resetting the daemon (--fix)"
if "$CLI" daemon refresh 2>&1 | redact; [ "${PIPESTATUS[0]}" -ne 0 ]; then
  # Fallback for a CLI without a working `daemon` command: stop the pid, clear
  # the socket dir. Only touches willow's own per-user dir.
  echo "'daemon refresh' failed; falling back to stopping the pid manually."
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null; then echo "Stopped daemon pid $pid."; fi
  fi
  rm -rf "$SOCK_DIR" 2>/dev/null || true
fi

say "4b. Retrying WITH a fresh daemon"
hr
if try_listing fresh-daemon; then
  hr
  echo "SUCCESS: a stale daemon was the problem. A fresh one works."
  rm -rf "$LOG_DIR"
  exit 0
fi
hr
echo "Still failing with a fresh daemon."
show_log_tail fresh-daemon

say "5. Retrying WITHOUT the daemon (direct connection)"
WAS_DISABLED=0
case "$DAEMON_STATUS" in *"disabled"*) WAS_DISABLED=1 ;; esac
if [ "$WAS_DISABLED" -eq 1 ]; then
  echo "The daemon was already disabled, so there is nothing to isolate."
else
  "$CLI" daemon disable 2>&1 | redact
  hr
  if try_listing no-daemon; then
    hr
    echo "SUCCESS with the daemon off -> the daemon layer was the problem."
    if [ "$KEEP_DISABLED" -eq 1 ]; then
      echo "Leaving the daemon DISABLED as requested. Re-enable later with: $CLI daemon enable"
    else
      "$CLI" daemon enable 2>&1 | redact
      echo "Daemon re-enabled (it was on before). If it keeps breaking, re-run with"
      echo "--fix --disable-daemon to leave it off."
    fi
    rm -rf "$LOG_DIR"
    exit 0
  fi
  hr
  show_log_tail no-daemon
  "$CLI" daemon enable 2>&1 | redact
  echo "Daemon setting restored to enabled."
fi

echo
echo "Still failing even without the daemon -> the bottleneck is the gateway,"
echo "network, TLS or auth, NOT the local daemon."

GATEWAY_URL="${WILLOW_GATEWAY_URL:-}"
if [ -z "$GATEWAY_URL" ] && [ -f "$CONFIG_PATH" ] && command -v node >/dev/null 2>&1; then
  GATEWAY_URL="$(node -e '
    try {
      const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
      process.stdout.write(c.baseUrl || (c.org ? "https://" + c.org + ".mcp-s.com/mcp" : ""))
    } catch (e) {}
  ' "$CONFIG_PATH" 2>/dev/null)"
fi
if [ -n "$GATEWAY_URL" ] && command -v curl >/dev/null 2>&1; then
  say "Gateway reachability (no credentials sent)"
  echo "url: $GATEWAY_URL"
  curl -sS -o /dev/null --max-time 15 \
    -w "http_status=%{http_code} time=%{time_total}s dns=%{time_namelookup}s tls=%{time_appconnect}s\n" \
    "$GATEWAY_URL" 2>&1 | redact
  echo "(401 = reachable and asking for a token; 000 = no response: network, VPN, proxy, DNS or TLS)"
else
  echo "Check the gateway yourself: curl -sS -o /dev/null -w \"%{http_code} %{time_total}s\\n\" <your gateway URL from 'willow config show'>"
fi
echo
echo "Next: look at the 'Network' and 'MCP transport' sections of the doctor output above"
echo "(proxy, extra CA certs, TLS). Logs are in $LOG_DIR. Review them, then send them to support."
exit 2
