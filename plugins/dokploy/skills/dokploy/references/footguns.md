# Dokploy Footguns

Known bugs, API sharp edges, and production gotchas. Read before first deploy.

---

## `application.saveBuildType` silently no-ops

`POST /api/application.saveBuildType` returns 200 OK but does NOT persist `buildType` or `dockerfile`. The application keeps whatever was inferred at create-time (usually `nixpacks`). There's no error to catch.

**Workaround**: set build type via `application.update` instead:

```bash
curl -sS -X POST "$DOKPLOY_URL/api/application.update" \
  -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"applicationId\":\"$APP_ID\",\"buildType\":\"dockerfile\",\"dockerfile\":\"Dockerfile\",\"dockerContextPath\":\"/\"}"
```

Always verify with `application.one` — if `buildType` is still `nixpacks` after a `save`, the save didn't take.

---

## `application.saveEnvironment` requires every field, including `createEnvFile`

The endpoint's zod schema is non-optional for `createEnvFile`. Omitting it returns:

```
400 BAD_REQUEST  createEnvFile: Invalid input: expected nonoptional, received undefined
```

Always pass `{applicationId, env, buildArgs, buildSecrets, createEnvFile}` with **all five** fields. Use empty strings for fields you don't need. `scripts/env-push.sh` handles this.

---

## "deploy done" ≠ "container running"

`applicationStatus: "done"` only means the build+swarm-create finished. The container can immediately crashloop on missing env (e.g., `BetterAuthError: default secret`). The Dokploy dashboard will happily show a green deploy while Traefik returns 502 for the domain.

After every first-time deploy:

1. `curl -sSI https://<domain>/` — expect 200/30x, not 502.
2. If 502, check `ssh vps "docker service ps <appName>"` for `Failed` tasks.
3. `docker service logs <appName> --tail 40` shows the crash reason.

---

## Bug #927 — Resource limits break deploys

**Never set `cpuLimit` or `memoryLimit` via the API or MCP on any resource (apps or databases).**

Dokploy mis-converts these values — CPU `"100"` becomes `1e-07`, memory `"1024"` is treated as bytes instead of MB. Setting limits through the API silently breaks subsequent deploys.

**Workaround**: Use the Dokploy dashboard UI to set resource limits. The dashboard applies correct conversions.

---

## `database.stop` is destructive

Calling `postgres.stop` / `mysql.stop` / `redis.stop` / `mongo.stop` / `mariadb.stop` does NOT pause the database. **It removes the entire Docker Swarm service.** The data volume may also be removed depending on Dokploy version.

**Workaround**: Use the dashboard UI to pause a database. If you must use the API, understand you are performing a full teardown.

Always confirm with the user before calling any `<type>.stop` or `<type>.remove`.

---

## `NEXT_PUBLIC_*` vars must be build args, not env vars

Next.js inlines `NEXT_PUBLIC_*` at build time. Setting them via `env` does nothing at the client layer — the build has already happened.

**Rule**: put `NEXT_PUBLIC_*` in `buildArgs`, put server-only secrets in `env`.

`scripts/env-push.sh` auto-splits a local `.env` along this boundary. If you're setting env vars manually via the API, split them yourself.

Same principle applies to any build-time framework var: Vite `VITE_*`, SvelteKit `PUBLIC_*`, etc. Check your framework's docs.

---

## Never set `externalPort` in production

Database and app endpoints can be given `externalPort` to expose a port directly on the VPS host. In production, this bypasses Traefik and the firewall, exposing the service to the public internet on an arbitrary port.

Use the internal `dokploy-network` for service-to-service traffic. External access should go through Traefik-managed domains with HTTPS.

---

## API envelope inconsistency

The plain `/api/<route>` endpoints return flat JSON. The legacy `/api/trpc/<route>` endpoints wrap bodies and responses in a `{"json": ...}` / `{"result":{"data":{"json":...}}}` envelope.

**Backup endpoints (`backup.listBackupFiles`, `backup.manualBackupPostgres`) are trpc-wrapped.** Most other endpoints are flat. When constructing a curl, check the API reference.

---

## Env var changes don't auto-deploy

`application.saveEnvironment` only persists config. The container is not restarted and the new vars aren't active until the next deploy.

Always ask the user whether to redeploy after pushing env changes. `scripts/env-push.sh` prints a reminder but does not deploy.

---

## Deployment logs are on the VPS, not in the API

The Dokploy API exposes runtime monitoring (`application.readAppMonitoring`) but NOT build logs. Build output lives in `/etc/dokploy/logs/<appName>/` on the server. You need SSH access to read it.

---

## Traefik doesn't auto-recover

Traefik runs as a standalone Docker container, not a Swarm service. When the VPS reboots, Swarm services come back automatically but Traefik does not. The symptom: dashboard and all deployed sites return connection refused / ERR_SSL.

**Fix**:
```bash
ssh "$DOKPLOY_SSH_HOST" "docker start dokploy-traefik"
```

Consider a `@reboot` cron or systemd unit on the VPS to make this automatic.

---

## Docker networking

Containers on the same Dokploy instance share the `dokploy-network` bridge. Use the container's `appName` as the hostname for inter-service communication:

```
postgresql://user:pass@<appName>:5432/dbname
redis://<appName>:6379
http://<appName>:3000
```

No external port exposure or DNS setup required for internal traffic. This is the safest pattern — see "Never set externalPort" above.
