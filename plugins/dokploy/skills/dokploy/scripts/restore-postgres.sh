#!/usr/bin/env bash
# Restore a Postgres database running as a Dokploy Swarm service from an
# S3-compatible object store (Cloudflare R2, AWS S3, Backblaze B2, MinIO).
#
# Stream: rclone cat (remote) | gunzip | docker exec pg_restore (remote)
#
# Required env vars:
#   DOKPLOY_SSH_HOST    e.g. root@1.2.3.4 or an ~/.ssh/config alias
#   S3_ACCESS_KEY       object storage access key
#   S3_SECRET_KEY       object storage secret key
#   S3_ENDPOINT         e.g. https://<account>.r2.cloudflarestorage.com
#   S3_PROVIDER         rclone provider name (defaults to "Cloudflare")
#
# Arguments:
#   $1 SWARM_SERVICE    Swarm service label (e.g. sambu-postgres-f5ekek)
#   $2 DB_NAME          database name
#   $3 DB_USER          database user
#   $4 S3_BUCKET        bucket name
#   $5 BACKUP_PATH      key of backup object within bucket (e.g. prefix/file.dump.gz)
#
# Assumes the backup is gzipped pg_dump -Fc format. rclone must be installed on the VPS.

set -euo pipefail

: "${DOKPLOY_SSH_HOST:?DOKPLOY_SSH_HOST must be set (e.g. root@1.2.3.4)}"
: "${S3_ACCESS_KEY:?S3_ACCESS_KEY must be set}"
: "${S3_SECRET_KEY:?S3_SECRET_KEY must be set}"
: "${S3_ENDPOINT:?S3_ENDPOINT must be set}"
S3_PROVIDER="${S3_PROVIDER:-Cloudflare}"

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <swarm-service> <db-name> <db-user> <s3-bucket> <backup-path>" >&2
    exit 2
fi

SERVICE="$1"
DB_NAME="$2"
DB_USER="$3"
BUCKET="$4"
BACKUP="$5"

echo "→ Finding running container for Swarm service: $SERVICE" >&2
CID=$(ssh "$DOKPLOY_SSH_HOST" \
    "docker ps -q --filter 'status=running' --filter 'label=com.docker.swarm.service.name=$SERVICE' | head -n1")

if [[ -z "$CID" ]]; then
    echo "Error: no running container for service '$SERVICE' on $DOKPLOY_SSH_HOST" >&2
    exit 1
fi

echo "→ Container: $CID" >&2
echo "→ Restoring $BUCKET/$BACKUP into $DB_NAME (user: $DB_USER)..." >&2
echo "  This overwrites current data in $DB_NAME." >&2

# shellcheck disable=SC2029  # intentional client-side expansion of arguments
ssh "$DOKPLOY_SSH_HOST" "rclone cat \
    --s3-provider='$S3_PROVIDER' \
    --s3-access-key-id='$S3_ACCESS_KEY' \
    --s3-secret-access-key='$S3_SECRET_KEY' \
    --s3-region='auto' \
    --s3-endpoint='$S3_ENDPOINT' \
    --s3-no-check-bucket \
    --s3-force-path-style \
    ':s3:$BUCKET/$BACKUP' \
    | gunzip \
    | docker exec -i $CID sh -c \"pg_restore -U '$DB_USER' -d $DB_NAME -O --clean --if-exists\""

echo "✓ Restore complete. Verify with a sample query:" >&2
echo "  ssh $DOKPLOY_SSH_HOST \"docker exec $CID psql -U $DB_USER -d $DB_NAME -c 'SELECT count(*) FROM <table>;'\"" >&2
