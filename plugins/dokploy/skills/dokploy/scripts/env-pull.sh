#!/usr/bin/env bash
# Dump remote env + buildArgs for an application to stdout.
#
# Usage:
#   env-pull.sh <applicationId>            # KEY=value lines, env then buildArgs
#   env-pull.sh <applicationId> --json     # full application JSON (for debugging)

set -euo pipefail
# shellcheck source=_auth.sh
source "$(dirname "$0")/_auth.sh"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <applicationId> [--json]" >&2
    exit 2
fi

APP_ID="$1"
MODE="${2:-plain}"

RESPONSE=$(curl -sS --fail-with-body -G "$API/application.one" \
    --data-urlencode "applicationId=$APP_ID" \
    -H "$AUTH_HEADER")

if [[ "$MODE" == "--json" ]]; then
    echo "$RESPONSE" | jq .
else
    echo "$RESPONSE" | jq -r '(.env // ""), (.buildArgs // "")' \
        | awk 'NF && !/^#/ { print }'
fi
