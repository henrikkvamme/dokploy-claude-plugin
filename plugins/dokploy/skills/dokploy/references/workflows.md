# Dokploy Workflows

Step-by-step guides for common operations. Auth: every curl call needs `-H "x-api-key: $DOKPLOY_TOKEN"`. Base URL: `$DOKPLOY_URL/api/`.

See `api.md` for full endpoint tables and `footguns.md` before touching resource limits or destructive ops.

---

## Host a new project

1. **Create project**
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/project.create" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d '{"name":"my-project","description":"..."}'
   ```
   Save the returned `projectId`.

2. **Get `environmentId`** — each project has a default "production" env.
   ```bash
   curl -sS -G "$DOKPLOY_URL/api/project.one" \
     --data-urlencode "projectId=$PROJECT_ID" \
     -H "x-api-key: $DOKPLOY_TOKEN" | jq '.environments[0].environmentId'
   ```

3. **Get `githubId`** (if deploying from GitHub)
   ```bash
   curl -sS "$DOKPLOY_URL/api/gitProvider.getAll" \
     -H "x-api-key: $DOKPLOY_TOKEN" | jq '.[] | {githubId: .gitProviderId, name: .name}'
   ```

4. **Create application**
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/application.create" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"name\":\"my-app\",\"appName\":\"my-app\",\"projectId\":\"$PROJECT_ID\",\"environmentId\":\"$ENV_ID\"}"
   ```
   Save the `applicationId`.

5. **Configure git source**
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/application.saveGithubProvider" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"applicationId\":\"$APP_ID\",\"repository\":\"my-repo\",\"owner\":\"my-user\",\"branch\":\"main\",\"githubId\":\"$GITHUB_ID\",\"buildPath\":\"/\"}"
   ```

6. **Set build type**
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/application.saveBuildType" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"applicationId\":\"$APP_ID\",\"buildType\":\"dockerfile\",\"dockerfile\":\"./Dockerfile\"}"
   ```

7. **Add domain**
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/domain.create" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"host\":\"myapp.example.com\",\"applicationId\":\"$APP_ID\",\"port\":3000,\"https\":true,\"certificateType\":\"letsencrypt\"}"
   ```
   DNS must point to the VPS first (A record → server IP).

8. **Push env vars** — use `scripts/env-push.sh` (handles `NEXT_PUBLIC_*` auto-split).

9. **Deploy**
   ```bash
   scripts/deploy.sh "$APP_ID"
   ```

---

## Update environment variables

Goal: sync a local `.env` file into the remote app, preserving server-specific keys.

1. Fetch current remote state
   ```bash
   scripts/env-pull.sh "$APP_ID" > /tmp/remote.env
   ```

2. Compute merged result (local values override remote; remote-only keys preserved; `NEXT_PUBLIC_*` → buildArgs).

3. **Skip server-specific keys that differ by design**: `DATABASE_URL`, `BETTER_AUTH_URL`, `NODE_ENV`, `HOSTNAME`, `PORT`.

4. Show the user **keys only** (never values). Confirm before pushing.

5. Push
   ```bash
   scripts/env-push.sh "$APP_ID" /path/to/.env
   ```

6. **Env var changes don't auto-deploy.** Ask the user whether to redeploy.

---

## Add a database

### Postgres / MySQL / Redis / Mongo / MariaDB

Same pattern — replace `<type>` with `postgres`, `mysql`, `redis`, `mongo`, `mariadb`.

1. Generate password
   ```bash
   openssl rand -base64 24 | tr -d '+/=' | head -c 24
   ```

2. Create
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/<type>.create" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"name\":\"...\",\"appName\":\"...\",\"databaseName\":\"...\",\"databaseUser\":\"...\",\"databasePassword\":\"...\",\"dockerImage\":\"postgres:16\",\"projectId\":\"$PROJECT_ID\",\"environmentId\":\"$ENV_ID\"}"
   ```

3. Deploy
   ```bash
   curl -sS -X POST "$DOKPLOY_URL/api/<type>.deploy" \
     -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"<type>Id\":\"$DB_ID\"}"
   ```

4. Connection string uses Docker hostname (the `appName`):
   ```
   postgresql://<user>:<pass>@<appName>:5432/<dbname>
   ```
   Never set `externalPort` in production — see `footguns.md`.

---

## Restore Postgres from backup

Dokploy's restore API is websocket-based. Easier to pipe the backup directly to `pg_restore` over SSH.

### Prerequisites

- `DOKPLOY_SSH_HOST` — e.g. `root@1.2.3.4`
- `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_ENDPOINT` — object storage credentials
- `S3_PROVIDER` — `Cloudflare`, `AWS`, `Minio`, `Other` (defaults to `Cloudflare`)
- `rclone` installed on the VPS

### Steps

1. **List available backups**
   ```bash
   INPUT="{\"json\":{\"destinationId\":\"$DEST_ID\",\"search\":\"$PREFIX\",\"serverId\":\"\"}}"
   curl -sS -G "$DOKPLOY_URL/api/trpc/backup.listBackupFiles" \
     --data-urlencode "input=$INPUT" \
     -H "x-api-key: $DOKPLOY_TOKEN" \
     | jq '.result.data.json[] | {name: .Name, sizeKB: (.Size/1024)}'
   ```

2. **Identify target container** on the VPS
   ```bash
   ssh "$DOKPLOY_SSH_HOST" "docker ps --filter label=com.docker.swarm.service.name=<service-name> --format '{{.ID}} {{.Names}}'"
   ```

3. **Confirm with user** — backup file, target database, that the restore overwrites current data.

4. **Run restore**
   ```bash
   scripts/restore-postgres.sh <swarm-service> <db-name> <db-user> <s3-bucket> <backup-path>
   ```

5. **Verify** — query a table to sanity-check rows are present.

### Notes

- Backups (`pg_dump -Fc`) are typically gzipped in object storage. `restore-postgres.sh` handles `gunzip` in-stream.
- Consider a manual backup first for safety:
  ```bash
  curl -sS -X POST "$DOKPLOY_URL/api/trpc/backup.manualBackupPostgres" \
    -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
    -d "{\"json\":{\"backupId\":\"$BACKUP_ID\"}}"
  ```

---

## Stop / teardown

### Applications
```bash
curl -sS -X POST "$DOKPLOY_URL/api/application.stop" \
  -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"applicationId\":\"$APP_ID\"}"

curl -sS -X POST "$DOKPLOY_URL/api/application.delete" \
  -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"applicationId\":\"$APP_ID\"}"
```

### Databases

**`<type>.stop` removes the Docker Swarm service entirely** — it is not a pause. Use the dashboard UI to pause. See `footguns.md`.

```bash
curl -sS -X POST "$DOKPLOY_URL/api/<type>.remove" \
  -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"<type>Id\":\"$DB_ID\"}"
```

Always confirm with the user before either operation.

---

## Monitor a deployment

### Build logs (SSH-only)

Dokploy writes build logs under `/etc/dokploy/logs/<appName>/` on the VPS.

```bash
ssh "$DOKPLOY_SSH_HOST" "ls -lt /etc/dokploy/logs/<appName>/ | head"
ssh "$DOKPLOY_SSH_HOST" "tail -100 /etc/dokploy/logs/<appName>/<logfile>"
```

### Runtime metrics

```bash
curl -sS -G "$DOKPLOY_URL/api/application.readAppMonitoring" \
  --data-urlencode "applicationId=$APP_ID" \
  -H "x-api-key: $DOKPLOY_TOKEN"
```

---

## Post-reboot checklist

Traefik runs as a standalone Docker container (not a Swarm service) and does NOT auto-recover after the VPS reboots. If the dashboard/sites are unreachable after a restart:

```bash
ssh "$DOKPLOY_SSH_HOST" "docker ps -f name=dokploy-traefik --format '{{.Status}}'"
ssh "$DOKPLOY_SSH_HOST" "docker start dokploy-traefik"   # if not running
ssh "$DOKPLOY_SSH_HOST" "docker service ls"              # verify Swarm services
ssh "$DOKPLOY_SSH_HOST" "ss -tlnp | grep ':443'"         # check for port conflicts
```
