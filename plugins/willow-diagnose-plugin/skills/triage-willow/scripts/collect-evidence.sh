#!/usr/bin/env bash
#
# Collect redacted, read-only evidence for triaging a Willow problem.
#
# Does NOT modify anything: no config writes, no process kills, no logins.
# It never prints tokens, auth files, headers or env values. Everything it does
# print passes through redact() (bearer tokens, JWTs, emails, secret-looking
# key/value pairs). Output goes to stdout only; redirect it to attach it to a
# support report:  bash collect-evidence.sh > willow-evidence.txt

set -u

CLI="${WILLOW_BIN:-willow}"
CONFIG_PATH="${WILLOW_CONFIG_PATH:-$HOME/.config/willow/config.json}"

redact() {
  sed -E \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+\/=-]+/Bearer [REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/[REDACTED_JWT]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/[A-Za-z0-9._+-]+%40[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/("?([Aa]ccess_?[Tt]oken|[Rr]efresh_?[Tt]oken|[Tt]oken|[Ss]ecret|[Aa]pi_?[Kk]ey|[Aa]uthorization|[Pp]assword|userAccessKey)"?[[:space:]]*[:=][[:space:]]*)"?[^",[:space:]}]+"?/\1"[REDACTED]"/g'
}

section() { printf '\n== %s\n' "$1"; }

section "Environment"
echo "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "os:    $(uname -srm)"
if command -v node >/dev/null 2>&1; then echo "node:  $(node -v)"; else echo "node:  not found"; fi
for var in HTTPS_PROXY HTTP_PROXY NO_PROXY NODE_EXTRA_CA_CERTS; do
  # Report only whether a network-shaping variable is set, never its value
  # (proxy URLs can carry credentials).
  eval "val=\${$var:-}"
  [ -n "$val" ] && echo "$var: set" || true
done

if ! command -v "$CLI" >/dev/null 2>&1; then
  section "willow CLI"
  echo "'$CLI' not found on PATH (set WILLOW_BIN to override). CLI checks skipped."
  CLI_OK=0
else
  CLI_OK=1
  section "willow --version"
  "$CLI" --version 2>&1 | redact
fi

if [ "$CLI_OK" -eq 1 ]; then
  section "willow auth status (exit 0 = signed in, 4 = must log in)"
  "$CLI" auth status 2>&1 | redact
  echo "exit code: ${PIPESTATUS[0]}"

  section "willow auth whoami"
  "$CLI" auth whoami 2>&1 | redact

  section "willow context list"
  "$CLI" context list 2>&1 | redact

  section "willow daemon status"
  "$CLI" daemon status 2>&1 | redact

  section "willow doctor"
  "$CLI" doctor 2>&1 | redact
fi

section "Gateway reachability (unauthenticated probe)"
GATEWAY_URL="${WILLOW_GATEWAY_URL:-}"
if [ -z "$GATEWAY_URL" ] && [ -f "$CONFIG_PATH" ] && command -v node >/dev/null 2>&1; then
  GATEWAY_URL="$(node -e '
    try {
      const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
      const u = c.baseUrl || (c.org ? "https://" + c.org + ".mcp-s.com/mcp" : "")
      process.stdout.write(u)
    } catch (e) {}
  ' "$CONFIG_PATH" 2>/dev/null)"
fi
if [ -z "$GATEWAY_URL" ]; then
  echo "No gateway URL found in $CONFIG_PATH."
  echo "Re-run with: WILLOW_GATEWAY_URL=https://<org>.withwillow.ai/mcp bash collect-evidence.sh"
fi
if [ -n "$GATEWAY_URL" ]; then
  echo "url: $GATEWAY_URL"
  case "$GATEWAY_URL" in
    https://*) ;;
    *) echo "WARNING: URL is not https://" ;;
  esac
  if command -v curl >/dev/null 2>&1; then
    # No credentials are sent. 401 means the gateway answered and wants a token.
    curl -sS -o /dev/null --max-time 15 \
      -w "http_status=%{http_code} time=%{time_total}s dns=%{time_namelookup}s tls=%{time_appconnect}s\n" \
      "$GATEWAY_URL" 2>&1 | redact
    echo "(401 = reachable; 000 = no response: network, VPN, proxy, DNS or TLS)"
  else
    echo "curl not found; probe skipped."
  fi
fi

section "Willow entries in MCP client configs (type + url only)"
if command -v node >/dev/null 2>&1; then
  node -e '
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
  ' 2>&1 | redact
else
  echo "node not found; config scan skipped."
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
fi

section "Done"
echo "Review the output above, then attach it to the support report."
