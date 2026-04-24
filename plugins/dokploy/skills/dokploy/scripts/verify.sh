#!/usr/bin/env bash
# Non-interactive diagnostic: reports which Dokploy env vars are set and
# whether the token actually authenticates. Safe for Claude to run — never
# echoes secret values (shows last 4 chars of secrets only).
#
# Exit codes:
#   0  required vars set and token validates
#   1  missing required var, missing dep, or token rejected

# Note: not using set -e; we want to run all checks even if some fail.
set -uo pipefail

if [[ -t 1 ]]; then
    bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
    green=$'\033[32m'; red=$'\033[31m'; yellow=$'\033[33m'
else
    bold=''; dim=''; reset=''; green=''; red=''; yellow=''
fi

tick="${green}✓${reset}"
cross="${red}✗${reset}"
warn="${yellow}○${reset}"

last4() {
    local v="$1"
    if [[ ${#v} -ge 4 ]]; then echo "...${v: -4}"; else echo "(set)"; fi
}

is_secret() {
    [[ "$1" == *TOKEN* || "$1" == *SECRET* || "$1" == *KEY* ]]
}

show_var() {
    local name="$1" level="$2"
    local val="${!name:-}"
    local display
    if is_secret "$name"; then display=$(last4 "$val"); else display="$val"; fi

    if [[ -n "$val" ]]; then
        printf "  %s %-22s ${dim}%s${reset}\n" "$tick" "$name" "$display"
        return 0
    fi

    case "$level" in
        required) printf "  %s %-22s ${red}not set${reset}\n"            "$cross" "$name" ;;
        optional) printf "  %s %-22s ${yellow}not set (optional)${reset}\n" "$warn"  "$name" ;;
    esac
    return 1
}

echo "${bold}Dokploy skill — environment check${reset}"
echo

echo "Required:"
required_ok=true
show_var DOKPLOY_URL   required || required_ok=false
show_var DOKPLOY_TOKEN required || required_ok=false

echo
echo "Optional — SSH / log / restore workflows:"
show_var DOKPLOY_SSH_HOST optional || true

echo
echo "Optional — Postgres restore from object storage:"
show_var S3_ACCESS_KEY optional || true
show_var S3_SECRET_KEY optional || true
show_var S3_ENDPOINT   optional || true
show_var S3_PROVIDER   optional || true

echo
echo "Dependencies:"
deps_ok=true
for cmd in curl jq; do
    if command -v "$cmd" >/dev/null; then
        printf "  %s %s\n" "$tick" "$cmd"
    else
        printf "  %s %s ${red}(missing)${reset}\n" "$cross" "$cmd"
        deps_ok=false
    fi
done

if ! $required_ok; then
    echo
    echo "${red}Setup incomplete.${reset} Required variables missing."
    echo "Run ${bold}in your terminal${reset} (not via Claude):"
    echo "    ${dim}bash ~/.claude/skills/dokploy/scripts/setup.sh${reset}"
    exit 1
fi

if ! $deps_ok; then
    echo
    echo "${red}Missing dependencies.${reset} Install with: brew install curl jq"
    exit 1
fi

echo
echo "API check:"
API="${DOKPLOY_URL%/}/api"
response=$(curl -sS --max-time 5 -w '\n%{http_code}' "$API/user.get" \
    -H "x-api-key: $DOKPLOY_TOKEN" 2>/dev/null || echo $'\n000')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

case "$http_code" in
    200)
        user=$(echo "$body" | jq -r '.email // .name // "authenticated"' 2>/dev/null || echo "authenticated")
        printf "  %s Reachable, token valid ${dim}(%s)${reset}\n" "$tick" "$user"
        echo
        echo "${green}Ready.${reset}"
        exit 0
        ;;
    401|403)
        printf "  %s Token rejected (HTTP %s)\n" "$cross" "$http_code"
        echo
        echo "Run setup.sh in your terminal to update: ${dim}bash ~/.claude/skills/dokploy/scripts/setup.sh${reset}"
        exit 1
        ;;
    000)
        printf "  %s Could not reach %s — check DOKPLOY_URL and network\n" "$cross" "$API"
        exit 1
        ;;
    *)
        printf "  %s Unexpected HTTP %s from %s\n" "$cross" "$http_code" "$API"
        exit 1
        ;;
esac
