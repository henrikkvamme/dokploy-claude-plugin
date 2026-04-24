#!/usr/bin/env bash
# Dump full application configuration as JSON.
#
# Usage:
#   app-info.sh <applicationId>

set -euo pipefail
# shellcheck source=_auth.sh
source "$(dirname "$0")/_auth.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <applicationId>" >&2
    exit 2
fi

curl -sS --fail-with-body -G "$API/application.one" \
    --data-urlencode "applicationId=$1" \
    -H "$AUTH_HEADER" \
    | jq .
