# Dokploy plugin for Claude Code

Operate a self-hosted [Dokploy](https://dokploy.com/) instance through Claude Code using curl and a small set of wrapper scripts. No third-party MCP server, no broken CLI, no Node/npm dependency — just your shell, `curl`, and `jq`.

## What it does

Gives Claude Code the knowledge and tools to:

- Host new projects end-to-end (project → app → git → build → domain → env → deploy)
- Push/pull environment variables with auto-split of `NEXT_PUBLIC_*` / `VITE_*` / `PUBLIC_*` into build args
- Create and deploy Postgres, MySQL, Redis, Mongo, and MariaDB databases
- Restore Postgres from S3-compatible object storage (Cloudflare R2, AWS S3, Backblaze B2, MinIO)
- Trigger deployments and tail build logs over SSH
- Handle post-reboot recovery (Traefik restart, Swarm service checks)

All operations go through Dokploy's documented HTTP API with explicit guardrails against known bugs (resource limit API corruption, destructive database stop, framework-specific build-arg requirements).

## Install

```
/plugin marketplace add henrikkvamme/dokploy-claude-plugin
/plugin install dokploy@henrikkvamme-plugins
```

After install, run the setup wizard **in your own terminal** (not through Claude):

```bash
bash ~/.claude/plugins/repos/henrikkvamme/dokploy-claude-plugin/plugins/dokploy/skills/dokploy/scripts/setup.sh
```

The wizard prompts for your Dokploy URL and API token, validates them, and writes them to `~/.claude/settings.json` so every Claude session picks them up automatically. Secrets are read silently — they never appear in your terminal output or in Claude's conversation context.

To verify setup at any time (Claude can run this):

```bash
bash ~/.claude/skills/dokploy/scripts/verify.sh
```

## Security model

The whole point of the wizard is that **your API token never touches Claude's conversation transcript**. Mechanisms:

1. The plugin's skill metadata tells Claude not to run `setup.sh` via the Bash tool
2. `setup.sh` itself has a TTY gate — it refuses to run without an interactive terminal
3. `verify.sh` is the Claude-safe diagnostic — it shows only the last 4 characters of secret values
4. Credentials live in `~/.claude/settings.json` (mode 600), not in shell rc files or repo

## What you need

| Required | For |
|---|---|
| `DOKPLOY_URL` | Everything |
| `DOKPLOY_TOKEN` | Everything |

| Optional | For |
|---|---|
| `DOKPLOY_SSH_HOST` | Log tailing, restore, post-reboot recovery |
| `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_ENDPOINT`, `S3_PROVIDER` | Postgres restore from backup |

All set by the setup wizard. No manual editing required.

## Usage

After setup, just talk to Claude about your Dokploy:

> "List my Dokploy projects"
> "Deploy the latest from the main branch of my `foo` app"
> "My env just got out of sync — pull the `.env` in `apps/web`, diff it against remote, push the changes"
> "Restore the sambu database from last night's backup"
> "My site is returning 503, can you check?"

Claude reads the skill's workflow guides, composes the right API calls, and asks for confirmation on anything destructive.

## What's NOT here

Intentionally left out to keep the plugin minimal:

- **No CLI binary** — scripts are plain bash, readable and auditable before running
- **No MCP server** — Dokploy's official API is simple enough that schema-typed tools add more noise than safety; half the operations weren't covered by the available MCP anyway
- **No opinionated framework support** — you bring the Dockerfile, `next.config.js`, etc.

See the skill's `references/` directory for the full API reference and workflow guides.

## Updates

```
/plugin update dokploy@henrikkvamme-plugins
```

Or refresh the marketplace catalog first:

```
/plugin marketplace update henrikkvamme-plugins
```

## Compatibility

Tested against Dokploy as of April 2026. The skill's `references/footguns.md` tracks known bugs in specific Dokploy versions — if an upstream fix lands, open an issue so the doc can be trimmed.

## License

MIT — see [`LICENSE`](LICENSE).

## Contributing

Open an issue or PR at https://github.com/henrikkvamme/dokploy-claude-plugin.

If you're reporting a Dokploy API behavior change, include:
- Your Dokploy version
- The endpoint and request body
- What the API returned vs what the scripts/docs expect
