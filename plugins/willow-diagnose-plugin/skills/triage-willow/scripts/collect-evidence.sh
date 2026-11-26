#!/usr/bin/env bash
#
# Collect redacted, read-only evidence for triaging a Willow problem.
#
# Built for the common case: an AI client (Cursor, Claude Code, VS Code, Codex,
# ...) connected to Willow over plain HTTP MCP. It needs only bash and curl.
# The `willow` CLI and Node.js are optional extras: used when present, skipped
# when not.
#
# Does NOT modify anything: no config writes, no process kills, no logins. It
# never prints tokens, auth files, headers or env values. Everything it prints
# passes through redact() (bearer tokens, JWTs, emails, secret-looking pairs).
# The only network traffic is unauthenticated requests to the Willow URLs the
# user's own clients already point at (query strings are stripped first).
#
# Output goes to stdout only:  bash collect-evidence.sh > willow-evidence.txt

set -u

CLI="${WILLOW_BIN:-willow}"
CONFIG_PATH="${WILLOW_CONFIG_PATH:-$HOME/.config/willow/config.json}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/willow-evidence.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
URLS="$WORK/urls"
: >"$URLS"

redact() {
  sed -E \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+\/=-]+/Bearer [REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/[REDACTED_JWT]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/[A-Za-z0-9._+-]+%40[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/("?([Aa]ccess_?[Tt]oken|[Rr]efresh_?[Tt]oken|[Tt]oken|[Ss]ecret|[Aa]pi_?[Kk]ey|[Aa]uthorization|[Pp]assword|userAccessKey)"?[[:space:]]*[:=][[:space:]]*)"?[^",[:space:]}]+"?/\1"[REDACTED]"/g'
}

section() { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------------------
section "Environment"
echo "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "os:    $(uname -srm)"
for var in HTTPS_PROXY HTTP_PROXY NO_PROXY NODE_EXTRA_CA_CERTS SSL_CERT_FILE; do
  # Report only whether a network-shaping variable is set, never its value
  # (proxy URLs can carry credentials).
  eval "val=\${$var:-}"
  [ -n "$val" ] && echo "$var: set" || true
done
command -v curl >/dev/null 2>&1 && echo "curl:  available" || echo "curl:  NOT found (endpoint probe will be skipped)"

# ---------------------------------------------------------------------------
section "Willow entries in MCP client configs (type + url only)"
if command -v node >/dev/null 2>&1; then
  URLS_OUT="$URLS" node -e '
    const fs = require("fs")
    const os = require("os")
    const path = require("path")
    const home = os.homedir()
    const files = [
      path.join(home, ".cursor", "mcp.json"),
      path.join(process.cwd(), ".cursor", "mcp.json"),
      path.join(process.cwd(), ".mcp.json"),
      path.join(process.cwd(), ".vscode", "mcp.json"),
      path.join(home, ".claude.json"),
      path.join(home, ".codeium", "windsurf", "mcp_config.json"),
    ]
    const looksWillow = (name, entry) =>
      /willow|withwillow|mcp-s/i.test(name + " " + (entry && (entry.url || entry.serverUrl || "")))
    const walk = (node, hits) => {
      if (!node || typeof node !== "object") return
      for (const key of ["mcpServers", "servers"]) {
        const group = node[key]
        if (group && typeof group === "object") {
          for (const [name, entry] of Object.entries(group)) {
            if (looksWillow(name, entry)) hits.push([name, entry])
          }
        }
      }
      for (const value of Object.values(node)) {
        if (value && typeof value === "object" && !Array.isArray(value)) walk(value, hits)
      }
    }
    let found = false
    const urls = []
    for (const file of files) {
      if (!fs.existsSync(file)) continue
      let json
      try { json = JSON.parse(fs.readFileSync(file, "utf8")) }
      catch (e) { console.log(file + ": exists but is not valid JSON"); found = true; continue }
      const hits = []
      walk(json, hits)
      for (const [name, entry] of hits) {
        found = true
        const url = entry.url || entry.serverUrl || undefined
        const warnings = []
        if (url && !/^https:\/\//i.test(url)) warnings.push("url does not start with https://")
        if (url && !/\/mcp(\/|\?|$)/.test(url)) warnings.push("url has no /mcp path")
        if (url && !entry.type) warnings.push("no type field (Cursor needs \"type\": \"http\")")
        if (url) urls.push(url)
        // Deliberately only these fields: headers, env and args can hold secrets.
        console.log(file + ": " + JSON.stringify({
          name,
          type: entry.type || "(missing)",
          url,
          command: entry.command || undefined,
          disabled: entry.disabled === true ? true : undefined,
          warnings: warnings.length ? warnings : undefined,
        }))
      }
    }
    if (!found) console.log("No Willow entry found in the common config files.")
    fs.writeFileSync(process.env.URLS_OUT, urls.join("\n") + "\n")
  ' 2>&1 | redact
else
  # No Node.js: a plainer scan that still catches URL typos.
  echo "(node not found: showing matching url lines only)"
  for f in "$HOME/.cursor/mcp.json" "$PWD/.cursor/mcp.json" "$PWD/.mcp.json" \
    "$PWD/.vscode/mcp.json" "$HOME/.claude.json" "$HOME/.codeium/windsurf/mcp_config.json"; do
    [ -f "$f" ] || continue
    grep -iE '"(url|serverUrl)"[[:space:]]*:[[:space:]]*"[^"]*(willow|mcp-s)' "$f" 2>/dev/null \
      | sed -E "s#^[[:space:]]*#$f: #" | redact
    grep -ioE '"(url|serverUrl)"[[:space:]]*:[[:space:]]*"https?://[^"]*(willow|mcp-s)[^"]*"' "$f" 2>/dev/null \
      | sed -E 's/^"[A-Za-z]+"[[:space:]]*:[[:space:]]*"//; s/"$//' >>"$URLS"
  done
fi

# Codex keeps MCP servers in TOML; show only url/command lines that mention Willow.
if [ -f "$HOME/.codex/config.toml" ]; then
  echo
  echo "$HOME/.codex/config.toml (willow url/command lines only):"
  grep -iE '^[[:space:]]*(url|command)[[:space:]]*=.*(willow|mcp-s)' "$HOME/.codex/config.toml" 2>/dev/null | redact || true
  if grep -iE "^[[:space:]]*url[[:space:]]*=[[:space:]]*['\"]?[^h'\"]" "$HOME/.codex/config.toml" 2>/dev/null \
    | grep -iE '(willow|mcp-s)' >/dev/null 2>&1; then
    echo "WARNING: a Willow url above does not start with https:// (typo such as 'ttps://'?)"
  fi
  if grep -iE "^[[:space:]]*url[[:space:]]*=[[:space:]]*['\"]?http://" "$HOME/.codex/config.toml" 2>/dev/null \
    | grep -iE '(willow|mcp-s)' >/dev/null 2>&1; then
    echo "WARNING: a Willow url uses http:// instead of https://"
  fi
  grep -ioE "^[[:space:]]*url[[:space:]]*=[[:space:]]*['\"]https?://[^'\"]*(willow|mcp-s)[^'\"]*['\"]" "$HOME/.codex/config.toml" 2>/dev/null \
    | sed -E "s/^[^'\"]*['\"]//; s/['\"]$//" >>"$URLS"
fi

# URL an optional CLI is configured with, or an explicit override.
if [ -n "${WILLOW_GATEWAY_URL:-}" ]; then
  echo "$WILLOW_GATEWAY_URL" >>"$URLS"
elif [ -f "$CONFIG_PATH" ] && command -v node >/dev/null 2>&1; then
  node -e '
    try {
      const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
      const u = c.baseUrl || (c.org ? "https://" + c.org + ".mcp-s.com/mcp" : "")
      if (u) process.stdout.write(u + "\n")
    } catch (e) {}
  ' "$CONFIG_PATH" 2>/dev/null >>"$URLS"
fi

# ---------------------------------------------------------------------------
section "Endpoint probe (unauthenticated; what a client sees before sign-in)"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"willow-triage-probe","version":"1"}}}'

probe() {
  local url="$1" origin code hdr="$WORK/h" body="$WORK/b" www status
  origin="$(printf '%s' "$url" | sed -E 's#^(https?://[^/]+).*#\1#')"
  echo "url: $url"
  code="$(curl -sS -D "$hdr" -o "$body" --max-time 15 -w '%{http_code}' -X POST "$url" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    -d "$INIT" 2>"$WORK/err")"
  if [ -s "$WORK/err" ]; then redact <"$WORK/err" | sed 's/^/  curl: /'; fi
  # The challenge carries no secret; drop the scheme word so the Bearer-token
  # redaction below can't mangle it, and still redact emails in the URL.
  www="$(grep -i '^www-authenticate:' "$hdr" 2>/dev/null | head -1 | tr -d '\r' \
    | sed -E 's/^[Ww][Ww][Ww]-[Aa]uthenticate:[[:space:]]*[Bb]earer[[:space:]]*//' | redact)"
  case "$code" in
    401)
      if [ -n "$www" ]; then
        status="OK  401 with an OAuth challenge: a Willow gateway answered and the client should start sign-in. (Does not prove the org or server name is right.)"
      else
        status="??  401 without a WWW-Authenticate challenge: not a normal Willow gateway answer."
      fi ;;
    200)
      if grep -qi '<html' "$body" 2>/dev/null; then
        status="BAD 200 + web page: this URL is the Willow portal, not the MCP endpoint. Probably missing /mcp."
      else
        status="??  200 without sign-in: unexpected for a Willow MCP URL."
      fi ;;
    404) status="BAD 404: path not found. Typo in the path, or no /mcp." ;;
    301|302|307|308)
      status="WARN redirect to $(grep -i '^location:' "$hdr" | head -1 | tr -d '\r' | cut -d' ' -f2- | sed -E 's/\?.*//'). A client may drop the POST on a redirect: use the final https URL directly." ;;
    403|429|5??) status="BAD $code: blocked, rate limited or the gateway is erroring. Compare with another network." ;;
    000) status="BAD no response: DNS, network, VPN, proxy or TLS. See the curl error above." ;;
    *) status="??  unexpected status $code" ;;
  esac
  echo "  POST initialize -> $code  $status"
  [ -n "$www" ] && echo "  challenge: $www"

  # OAuth discovery: what a client fetches after the 401 to learn where to sign
  # in. Once per host, since every URL on a host shares it.
  local d flag
  if ! grep -qxF "$origin" "$WORK/origins" 2>/dev/null; then
    echo "$origin" >>"$WORK/origins"
    for d in /.well-known/oauth-protected-resource /.well-known/oauth-authorization-server; do
      code="$(curl -sS -o /dev/null --max-time 15 -w '%{http_code}' "$origin$d" 2>/dev/null)"
      [ "$code" = "200" ] && flag="OK " || flag="BAD"
      echo "  GET  $d -> $code  $flag   (sign-in discovery for $origin)"
    done
  fi
}

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found; probe skipped."
else
  # Strip query strings (they can carry secrets) and de-duplicate.
  sed -E 's/\?.*$//; s/[[:space:]]+$//' "$URLS" | grep -E '^https?://' | sort -u >"$WORK/probe-urls"
  if [ -s "$WORK/probe-urls" ]; then
    while IFS= read -r u; do probe "$u"; echo; done <"$WORK/probe-urls"
    echo "How to read this: 401 + challenge is the NORMAL first step of OAuth, not a failure."
    echo "A proxy or firewall that blocks /.well-known, /authorize, /token or /register"
    echo "makes 'Authorize never completes'. A wrong org host or a typo in a server or"
    echo "toolkit name ALSO answers 401 here, so compare the host and names with what"
    echo "Connect MCP shows; a mismatch only surfaces after sign-in."
  else
    echo "No Willow URL found in the client configs above."
    echo "Re-run with: WILLOW_GATEWAY_URL=https://<org>.withwillow.ai/mcp bash collect-evidence.sh"
  fi
fi

# ---------------------------------------------------------------------------
section "willow CLI (optional)"
if ! command -v "$CLI" >/dev/null 2>&1; then
  echo "'$CLI' not installed. That's fine: the CLI is only one way to use Willow."
else
  echo "version:"; "$CLI" --version 2>&1 | redact

  echo; echo "auth status (exit 0 = signed in, 4 = must log in):"
  "$CLI" auth status 2>&1 | redact
  echo "exit code: ${PIPESTATUS[0]}"

  echo; echo "whoami:";        "$CLI" auth whoami 2>&1 | redact
  echo; echo "context list:";  "$CLI" context list 2>&1 | redact
  echo; echo "daemon status:"; "$CLI" daemon status 2>&1 | redact
  echo; echo "doctor:";        "$CLI" doctor 2>&1 | redact
fi

section "Done"
echo "Review the output above, then attach it to the support report."
