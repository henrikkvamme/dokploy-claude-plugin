# Dokploy plugin for Claude Code

Deploy and manage apps, databases, env vars, and backups on a self-hosted [Dokploy](https://dokploy.com/) instance from Claude Code.

## Install

```
/plugin marketplace add henrikkvamme/dokploy-claude-plugin
/plugin install dokploy@henrikkvamme-plugins
```

## Setup

Run the wizard **in your own terminal** (not through Claude — it won't let you):

```bash
bash ~/.claude/plugins/repos/henrikkvamme/dokploy-claude-plugin/plugins/dokploy/skills/dokploy/scripts/setup.sh
```

It prompts for your Dokploy URL and API token, validates them, and writes them to `~/.claude/settings.json`. Secrets are read silently and never appear in Claude's conversation.

## Use

Just talk to Claude about your Dokploy:

- "List my Dokploy projects"
- "Deploy the latest `main` of my `foo` app"
- "Pull the remote env for `bar`, diff against my local `.env`, push the changes"
- "Restore the `sambu` database from last night's backup"
- "My site is returning 503, can you check?"

## Requirements

- `curl`, `jq` (macOS: `brew install jq`)
- A Dokploy API token (dashboard → Profile → API Keys)

## Update

```
/plugin update dokploy@henrikkvamme-plugins
```

## License

MIT
