#!/usr/bin/env bash
# Interactive Dokploy setup wizard.
#
# Writes credentials to the "env" block of ~/.claude/settings.json so they are
# injected into every Claude Code session automatically. Backs up the existing
# settings.json to settings.json.bak before writing.
#
# MUST be run in a terminal (TTY required). The wizard refuses to run under
# Claude's Bash tool — the whole point is to keep your API token out of the
# conversation transcript.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

die() { echo "Error: $*" >&2; exit 1; }

# ── TTY gate ────────────────────────────────────────────────────────────────
if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    cat >&2 <<'EOF'
This setup wizard must be run interactively in your own terminal.

If you're seeing this message through Claude, open a terminal yourself and run:

    bash ~/.claude/skills/dokploy/scripts/setup.sh

Running the wizard directly keeps your Dokploy API token out of Claude's
conversation context.
EOF
    exit 1
fi

# ── Dependency check ───────────────────────────────────────────────────────
command -v jq   >/dev/null || die "jq is required.  Install: brew install jq"
command -v curl >/dev/null || die "curl is required."

# ── Settings file prep ─────────────────────────────────────────────────────
mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 \
    || die "$SETTINGS is not valid JSON. Fix it manually before running setup."

get() { jq -r ".env.$1 // empty" "$SETTINGS"; }

existing_url=$(get DOKPLOY_URL)
existing_ssh=$(get DOKPLOY_SSH_HOST)
existing_s3_endpoint=$(get S3_ENDPOINT)
existing_s3_provider=$(get S3_PROVIDER)

# ── Prompt helpers ─────────────────────────────────────────────────────────
# Prompts go to stderr (via read -p). Captured value goes to stdout.
prompt() {
    local label="$1" default="${2:-}" input
    if [[ -n "$default" ]]; then
        read -r -p "$label [$default]: " input
        echo "${input:-$default}"
    else
        read -r -p "$label: " input
        echo "$input"
    fi
}

prompt_secret() {
    local label="$1" input
    read -r -s -p "$label: " input
    echo >&2
    echo "$input"
}

confirm() {
    local label="$1" input
    read -r -p "$label [y/N]: " input
    [[ "$input" =~ ^[Yy]$ ]]
}

# ── Banner ──────────────────────────────────────────────────────────────────
cat <<'EOF'

╭──────────────────────────────────────────────╮
│  Dokploy skill — setup                       │
│                                              │
│  Writes credentials to ~/.claude/            │
│  settings.json (env block). Secrets are      │
│  read silently and never echoed back.        │
╰──────────────────────────────────────────────╯

EOF

# ── Required: URL + token ──────────────────────────────────────────────────
echo "── Dokploy instance ────────────────────────────"
DOKPLOY_URL=$(prompt "Dokploy URL" "${existing_url:-https://dokploy.example.com}")
DOKPLOY_URL="${DOKPLOY_URL%/}"
[[ -n "$DOKPLOY_URL" ]] || die "DOKPLOY_URL is required."

echo
cat <<EOF
Generate an API token in the Dokploy dashboard:

    $DOKPLOY_URL  →  Profile (top right)  →  API Keys  →  Generate

Suggested values:
    Name         Claude Skill
    Prefix       claude           (human-readable tag, not security-relevant)
    Expiration   6 or 12 months   (rotate on expiry — avoid "Never")
    Rate limit   off              (single-user personal use)
    Request cap  unlimited

Copy the token, then paste it below.

EOF
DOKPLOY_TOKEN=$(prompt_secret "API token (hidden)")
[[ -n "$DOKPLOY_TOKEN" ]] || die "DOKPLOY_TOKEN is required."

# ── Verify ──────────────────────────────────────────────────────────────────
echo
printf "Verifying against %s ... " "$DOKPLOY_URL"
http_code=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
    "$DOKPLOY_URL/api/user.get" -H "x-api-key: $DOKPLOY_TOKEN" 2>/dev/null || echo "000")

case "$http_code" in
    200) echo "✓ authenticated" ;;
    401|403) die "token rejected (HTTP $http_code). Re-run with a valid token." ;;
    000) die "could not reach $DOKPLOY_URL. Check the URL and your network." ;;
    *)   die "unexpected HTTP $http_code from $DOKPLOY_URL" ;;
esac

# ── Optional: SSH ───────────────────────────────────────────────────────────
echo
echo "── SSH (optional — log tailing, restore, post-reboot) ──"
if [[ -n "$existing_ssh" ]]; then
    DOKPLOY_SSH_HOST=$(prompt "SSH host (enter to keep, '-' to clear)" "$existing_ssh")
    [[ "$DOKPLOY_SSH_HOST" == "-" ]] && DOKPLOY_SSH_HOST="__CLEAR__"
else
    DOKPLOY_SSH_HOST=$(prompt "SSH host (blank to skip)")
fi

# ── Optional: S3 ────────────────────────────────────────────────────────────
echo
echo "── Object storage (optional — Postgres restore) ──"
echo
cat <<EOF
These are the same S3-compatible credentials you use for a Dokploy backup
"Destination". The fastest way to get them:

    $DOKPLOY_URL/dashboard/settings/destinations
    (or main dashboard → Settings → Destinations → click your destination)

    Copy the Access Key, Secret Key, and Endpoint from that page.

If you haven't configured a backup destination in Dokploy yet, skip this step
and come back later. You don't need S3 creds for normal deploy workflows —
only for Postgres restore.

Where to create keys by provider:
    Cloudflare R2    dash.cloudflare.com → R2 → Manage R2 API Tokens
                     Permission: Object Read & Write on the backups bucket
    AWS S3           IAM → create user with s3:GetObject on the backup bucket
    Backblaze B2     App Keys → create with readFiles on the bucket
    MinIO            self-hosted — use mc admin user add and policy attach

Endpoint URL format:
    Cloudflare R2    https://<account-id>.r2.cloudflarestorage.com
    AWS S3           https://s3.<region>.amazonaws.com
    Backblaze B2     https://s3.<region>.backblazeb2.com
    MinIO            https://<your-minio-host>

EOF
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_ENDPOINT=""
S3_PROVIDER=""
if confirm "Configure S3-compatible backup credentials?"; then
    S3_ACCESS_KEY=$(prompt_secret "Access key (hidden)")
    S3_SECRET_KEY=$(prompt_secret "Secret key (hidden)")
    S3_ENDPOINT=$(prompt "Endpoint URL" "${existing_s3_endpoint:-}")
    S3_PROVIDER=$(prompt "Provider [Cloudflare/AWS/Minio/Other]" "${existing_s3_provider:-Cloudflare}")
fi

# ── Write ───────────────────────────────────────────────────────────────────
echo
echo "── Writing to $SETTINGS ──"
cp "$SETTINGS" "${SETTINGS}.bak"
echo "  Backup: ${SETTINGS}.bak"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

jq \
    --arg url    "$DOKPLOY_URL" \
    --arg token  "$DOKPLOY_TOKEN" \
    --arg ssh    "$DOKPLOY_SSH_HOST" \
    --arg s3ak   "$S3_ACCESS_KEY" \
    --arg s3sk   "$S3_SECRET_KEY" \
    --arg s3end  "$S3_ENDPOINT" \
    --arg s3prov "$S3_PROVIDER" '
    .env = (.env // {})
    | .env.DOKPLOY_URL   = $url
    | .env.DOKPLOY_TOKEN = $token
    | if   $ssh    == "__CLEAR__" then del(.env.DOKPLOY_SSH_HOST)
      elif $ssh    != ""          then .env.DOKPLOY_SSH_HOST = $ssh
      else . end
    | if $s3ak   != "" then .env.S3_ACCESS_KEY = $s3ak   else . end
    | if $s3sk   != "" then .env.S3_SECRET_KEY = $s3sk   else . end
    | if $s3end  != "" then .env.S3_ENDPOINT   = $s3end  else . end
    | if $s3prov != "" then .env.S3_PROVIDER   = $s3prov else . end
' "$SETTINGS" > "$tmp"

mv "$tmp" "$SETTINGS"
trap - EXIT

wrote="DOKPLOY_URL, DOKPLOY_TOKEN"
case "$DOKPLOY_SSH_HOST" in
    "__CLEAR__") wrote="$wrote; cleared DOKPLOY_SSH_HOST" ;;
    "")          : ;;
    *)           wrote="$wrote, DOKPLOY_SSH_HOST" ;;
esac
[[ -n "$S3_ACCESS_KEY" ]] && wrote="$wrote, S3_ACCESS_KEY, S3_SECRET_KEY, S3_ENDPOINT, S3_PROVIDER"
echo "  Wrote: $wrote"

cat <<EOF

Done.

Open a new Claude session to pick up the env vars, then try:
    "show me my Dokploy projects"

To re-check setup at any time:
    bash ~/.claude/skills/dokploy/scripts/verify.sh
EOF
