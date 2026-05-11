# Dokploy API Reference

All Dokploy operations go through the tRPC HTTP API at `$DOKPLOY_URL/api/`.

## Auth

Header: `x-api-key: $DOKPLOY_TOKEN`

## Conventions

- **Reads**: `GET` with flat query params (e.g. `?applicationId=abc`)
- **Writes**: `POST` with flat JSON bodies
- **Responses**: direct JSON — no `result.data.json` envelope on the `/api/<route>` endpoints
- **Legacy tRPC endpoints** at `/api/trpc/<route>` DO use the envelope (used by some server-side endpoints like `backup.listBackupFiles`)

## Projects

| Endpoint | Method | Body / Params |
|---|---|---|
| `project.all` | GET | — (returns array) |
| `project.one` | GET | `projectId` |
| `project.create` | POST | `{name, description}` |
| `project.remove` | POST | `{projectId}` |

## Applications

| Endpoint | Method | Body / Params |
|---|---|---|
| `application.create` | POST | `{name, appName, projectId, environmentId}` |
| `application.one` | GET | `applicationId` — returns full config incl. `env`, `buildArgs`, `buildSecrets` |
| `application.update` | POST | config fields only (see below) — **do not** use for env/buildArgs |
| `application.saveEnvironment` | POST | `{applicationId, env, buildArgs, buildSecrets, createEnvFile}` |
| `application.saveGithubProvider` | POST | `{applicationId, repository, owner, branch, githubId, buildPath}` |
| `application.saveBuildType` | POST | ⚠️ returns success but **does not persist** — use `application.update` with `buildType` instead. See footguns. |
| `application.deploy` | POST | `{applicationId}` |
| `application.redeploy` | POST | `{applicationId}` |
| `application.stop` | POST | `{applicationId}` |
| `application.delete` | POST | `{applicationId}` |
| `application.readAppMonitoring` | GET | `applicationId` — CPU/memory stats |

### `application.update` config fields

| Field | Example | Notes |
|---|---|---|
| `sourceType` | `"github"` | `github`, `gitlab`, `gitea`, `bitbucket`, `docker`, `drop` |
| `repository` | `"my-repo"` | Repo name only (not full URL) |
| `owner` | `"my-user"` | GitHub username/org |
| `branch` | `"main"` | Branch to deploy |
| `buildType` | `"dockerfile"` | `dockerfile`, `nixpacks`, `heroku`, `railpack` |
| `buildPath` | `"/"` | Build context path |
| `dockerfile` | `"./Dockerfile"` | Required when `buildType=dockerfile` |
| `githubId` | `"Sf3P-..."` | From `gitProvider.getAll` |
| `autoDeploy` | `true` | Auto-deploy on push |

### `application.saveEnvironment` fields

All env-style fields are newline-separated `KEY=value` strings. **All fields below are required** — the API rejects payloads missing any of them with a 400 zod error. Pass empty strings (`""`) for fields you don't need.

| Field | Purpose |
|---|---|
| `applicationId` | Required |
| `env` | Runtime env vars (container start) |
| `buildArgs` | Docker build args — **`NEXT_PUBLIC_*` vars MUST go here**, see footguns |
| `buildSecrets` | Docker build secrets |
| `createEnvFile` | Bool — write env vars to `.env` in container. **Required field**, not optional. |

## Volume mounts

Mount endpoints live at `mounts.*` (plural) and use `serviceId` + `serviceType`, **not** `applicationId`. Not obvious from naming — easy to miss.

| Endpoint | Method | Body |
|---|---|---|
| `mounts.create` | POST | `{type, mountPath, serviceType, serviceId, volumeName?, hostPath?, filePath?, content?}` |

### `mounts.create` fields

| Field | Example | Notes |
|---|---|---|
| `type` | `"volume"` | `volume`, `bind`, `file` |
| `mountPath` | `"/app/data"` | Path inside the container |
| `serviceType` | `"application"` | `application`, `postgres`, `mysql`, `redis`, `mongo`, `mariadb`, `compose`, `libsql` |
| `serviceId` | `"$APP_ID"` | The `applicationId` (or `postgresId`, etc.) — name doesn't match the field |
| `volumeName` | `"myapp-data"` | Required when `type=volume` |
| `hostPath` | `"/host/path"` | Required when `type=bind` |
| `filePath`, `content` | — | Required when `type=file` |

Example — attach a persistent volume to an application:
```bash
curl -sS -X POST "$DOKPLOY_URL/api/mounts.create" \
  -H "x-api-key: $DOKPLOY_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"type\":\"volume\",\"volumeName\":\"myapp-data\",\"mountPath\":\"/app/data\",\"serviceType\":\"application\",\"serviceId\":\"$APP_ID\"}"
```

Mounts only take effect on the next deploy.

## Domains

| Endpoint | Method | Body |
|---|---|---|
| `domain.create` | POST | `{host, applicationId, port, https, certificateType}` |

Typical HTTPS domain: `{"host":"foo.example.com","applicationId":"...","port":3000,"https":true,"certificateType":"letsencrypt"}`

## Git Providers

| Endpoint | Method | Params |
|---|---|---|
| `gitProvider.getAll` | GET | — |

## Deployments

| Endpoint | Method | Params |
|---|---|---|
| `deployment.all` | GET | `applicationId` |

## Databases

Replace `<type>` with: `postgres`, `mysql`, `mongo`, `redis`, `mariadb`.

| Endpoint | Method | Body |
|---|---|---|
| `<type>.create` | POST | `{name, appName, databaseName, databaseUser, databasePassword, dockerImage, projectId, environmentId}` |
| `<type>.one` | GET | `<type>Id` (e.g. `postgresId`) |
| `<type>.deploy` | POST | `{<type>Id}` |
| `<type>.stop` | POST | `{<type>Id}` — **destructive**, see footguns |
| `<type>.remove` | POST | `{<type>Id}` |

## Environments

Every app and database create call requires an `environmentId`. Fetch via `project.one?projectId=...` — each project has a default "production" environment.

## Backups (legacy tRPC envelope)

Backup endpoints use `/api/trpc/<route>` and require a wrapped body: `{"json": {...}}`. Responses come back as `{result: {data: {json: ...}}}`.

| Endpoint | Method | Notes |
|---|---|---|
| `backup.listBackupFiles` | GET | Input via `--data-urlencode 'input={"json":{"destinationId":"...","search":"prefix","serverId":""}}'` |
| `backup.manualBackupPostgres` | POST | Body: `{"json":{"backupId":"..."}}` |

Restore is websocket-based — do it over SSH with `pg_restore` directly, not via the API. See `workflows.md`.

## User

| Endpoint | Method | Params |
|---|---|---|
| `user.get` | GET | — |

## Docker Networking

Containers on the same Dokploy instance share the `dokploy-network` bridge. Use the container's `appName` (returned from create calls) as the hostname for inter-service communication:

```
postgresql://<dbUser>:<dbPass>@<appName>:5432/<dbName>
redis://<appName>:6379
```

No external port exposure needed for internal traffic.
