#!/usr/bin/env bash
# Push a local dotenv file to a Dokploy application.
#
# Auto-splits NEXT_PUBLIC_* (and common framework equivalents) into buildArgs.
# Everything else goes into env.
#
# Usage:
#   env-push.sh <applicationId> <dotenv-path>

set -euo pipefail
# shellcheck source=_auth.sh
source "$(dirname "$0")/_auth.sh"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <applicationId> <dotenv-path>" >&2
    exit 2
fi

APP_ID="$1"
DOTENV="$2"

[[ -f "$DOTENV" ]] || { echo "Error: $DOTENV not found" >&2; exit 1; }

ENV_VARS=""
BUILD_ARGS=""

while IFS= read -r line || [[ -n "$line" ]]; do
    # skip blanks and comments
    [[ -z "${line// /}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # strip leading/trailing whitespace
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    # build-time framework vars go to buildArgs
    if [[ "$trimmed" =~ ^(NEXT_PUBLIC_|VITE_|PUBLIC_|REACT_APP_|EXPO_PUBLIC_|GATSBY_|NUXT_PUBLIC_) ]]; then
        BUILD_ARGS+="${trimmed}"$'\n'
    else
        ENV_VARS+="${trimmed}"$'\n'
    fi
done < "$DOTENV"

PAYLOAD=$(jq -n \
    --arg id "$APP_ID" \
    --arg env "$ENV_VARS" \
    --arg buildArgs "$BUILD_ARGS" \
    '{applicationId: $id, env: $env, buildArgs: $buildArgs}')

# Print keys only (never values) so transcripts/logs don't leak secrets
echo "→ Pushing env to $APP_ID" >&2
echo "  env keys:"       >&2
echo "$ENV_VARS"   | grep -oE '^[^=]+' | sed 's/^/    /' >&2
echo "  buildArg keys:"  >&2
echo "$BUILD_ARGS" | grep -oE '^[^=]+' | sed 's/^/    /' >&2

curl -sS --fail-with-body -X POST "$API/application.saveEnvironment" \
    -H "$AUTH_HEADER" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD" \
    | jq -r 'if .applicationId then "✓ Saved (applicationId: " + .applicationId + ")" else . end'

echo "→ Env var changes do NOT auto-deploy. Run scripts/deploy.sh $APP_ID to apply." >&2
