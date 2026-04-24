---
name: dokploy
description: Deploy and manage applications, databases, env vars, domains, and backups on a self-hosted Dokploy instance. Use when the user mentions deploying, hosting, their VPS, Dokploy, Postgres/MySQL/Redis/Mongo/MariaDB, env vars, build args, domains, SSL certs, Let's Encrypt, backup or restore, or says things like "my app is down", "deploy broke", "503", or "my site isn't loading" in an infra context.
---

# Dokploy

Operate a self-hosted Dokploy instance through its tRPC HTTP API using curl and a small set of wrapper scripts. No external CLI or MCP server required.

## Prerequisites

Two environment variables are required: `DOKPLOY_URL` and `DOKPLOY_TOKEN`. Optional extras exist for SSH and S3 workflows.

### First-time setup

Before using the skill, the user runs the setup wizard **in their own terminal**:

```bash
bash ~/.claude/skills/dokploy/scripts/setup.sh
```

The wizard prompts for the URL and API token, validates them against the Dokploy API, and writes the values into `~/.claude/settings.json` (`env` block). It reads secrets silently and backs up `settings.json` before writing.

**`setup.sh` refuses to run without a TTY.** Its purpose is to keep the token out of Claude's conversation context — see the "Rules" section below.

### Checking setup state

`scripts/verify.sh` is safe for Claude to run. It reports which env vars are set (secrets shown as last-4 only), validates the token against the API, and reports exactly what's missing. Use it to diagnose before any operation, especially if scripts start failing.

```bash
bash ~/.claude/skills/dokploy/scripts/verify.sh
```

For manual setup without the wizard, see `references/setup.md`.

## How to brief this skill

For any non-trivial op (new project, DB creation, restore, multi-var env push), give a full-context brief up front:

- **Goal** — what success looks like
- **Constraints** — what not to touch, API contracts, performance budgets
- **Acceptance criteria** — how to verify

Example:
> Goal: host a fresh Next.js app `foo` from `github.com/me/foo` branch `main`.
> Constraints: dockerfile build type, no resource limits (bug #927), non-root Dockerfile user.
> Acceptance: reachable at `foo.example.com` with Let's Encrypt cert, `/api/health` returns 200.

Thin prompts ("deploy foo") produce more clarifying questions and worse outputs.

## Workflows

See `references/workflows.md` for full guides:

- **Host a new project** — project → app → git → build → domain → env → deploy
- **Update environment variables** — merge local `.env` into remote, respecting `NEXT_PUBLIC_*` rules
- **Add a database** — Postgres, MySQL (full API support); Redis, Mongo, MariaDB (same pattern)
- **Restore Postgres from backup** — S3-compatible object storage → `pg_restore` via SSH
- **Stop / teardown** — app stop/delete, database stop/remove
- **Monitor a deployment** — build logs, metrics
- **Post-reboot checklist** — Traefik recovery, service verification

## Convenience scripts

Each script takes positional args, reads config from env, fails loudly. Read the script header for usage.

| Script | Purpose | Claude-safe? |
|---|---|---|
| `scripts/setup.sh` | Interactive setup wizard (writes to settings.json) | ✗ user runs in own terminal |
| `scripts/verify.sh` | Diagnostic — reports env state, validates token | ✓ |
| `scripts/env-push.sh` | Push a local `.env` file to an app (auto-separates `NEXT_PUBLIC_*` → buildArgs) | ✓ |
| `scripts/env-pull.sh` | Dump remote env + buildArgs to stdout | ✓ |
| `scripts/deploy.sh` | Trigger a deployment | ✓ |
| `scripts/app-info.sh` | Dump full app config as JSON | ✓ |
| `scripts/restore-postgres.sh` | Restore Postgres from S3-compatible backup | ✓ (confirm with user first) |

Scripts source `_auth.sh` to validate env vars and compute `$API`. Run directly from the skill directory or reference by absolute path.

## References

- `references/api.md` — tRPC endpoint tables
- `references/workflows.md` — step-by-step guides
- `references/footguns.md` — known Dokploy bugs and API gotchas (read before first deploy)
- `references/setup.md` — first-time configuration

## Rules

- **Never run `setup.sh` via the Bash tool.** It's gated behind a TTY check and will refuse, but more importantly: the wizard prompts for the API token, and running it through Claude would capture the token in the conversation transcript. If the user hasn't set up yet, instruct them to run `bash ~/.claude/skills/dokploy/scripts/setup.sh` in their own terminal. Use `verify.sh` (which is Claude-safe) to diagnose setup state.
- **Never log env var values.** Print keys only. Secrets shown in `verify.sh` output are truncated to last-4.
- **Confirm destructive ops.** DB stop/remove, app delete, restore, env overwrite — always ask first.
- **Read `references/footguns.md` before touching resource limits or database stop.** Several Dokploy APIs have sharp edges.
- **Env var changes don't auto-deploy.** Ask the user whether to redeploy after pushing env.
