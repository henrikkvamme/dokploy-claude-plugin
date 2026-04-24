#!/usr/bin/env bash
# Trigger a deployment for an application.
#
# Usage:
#   deploy.sh <applicationId>

set -euo pipefail
# shellcheck source=_auth.sh
source "$(dirname "$0")/_auth.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <applicationId>" >&2
    exit 2
fi

APP_ID="$1"

curl -sS --fail-with-body -X POST "$API/application.deploy" \
    -H "$AUTH_HEADER" \
    -H 'Content-Type: application/json' \
    -d "{\"applicationId\":\"$APP_ID\"}" \
    | jq .

echo "→ Deployment triggered. Tail build logs via SSH at /etc/dokploy/logs/<appName>/" >&2
