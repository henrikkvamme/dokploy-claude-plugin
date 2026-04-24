#!/usr/bin/env bash
# Sourced by sibling scripts. Validates required env vars and computes $API.
#
# Required in caller's environment:
#   DOKPLOY_URL      e.g. https://dokploy.example.com
#   DOKPLOY_TOKEN    API token from Dokploy dashboard

: "${DOKPLOY_URL:?DOKPLOY_URL must be set (e.g. https://dokploy.example.com)}"
: "${DOKPLOY_TOKEN:?DOKPLOY_TOKEN must be set (get from Dokploy dashboard -> Profile -> API Keys)}"

API="${DOKPLOY_URL%/}/api"
AUTH_HEADER="x-api-key: $DOKPLOY_TOKEN"

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
