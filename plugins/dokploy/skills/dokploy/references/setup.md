# Setup

First-time configuration for using this skill against your own Dokploy instance.

## Recommended: run the wizard

```bash
bash ~/.claude/skills/dokploy/scripts/setup.sh
```

Must be run in your own terminal (not via Claude). The wizard prompts for URL, token, and optional SSH/S3 credentials; validates the token against the Dokploy API; writes everything into the `env` block of `~/.claude/settings.json`. Secrets are read silently.

To re-check configuration later:
```bash
bash ~/.claude/skills/dokploy/scripts/verify.sh
```

The rest of this document is for manual setup — skip it unless you have a reason not to use the wizard.

---

## Manual setup (alternative)

Two environment variables.

### `DOKPLOY_URL`

Base URL of your Dokploy dashboard (no trailing slash).

```bash
export DOKPLOY_URL="https://dokploy.example.com"
```

### `DOKPLOY_TOKEN`

API token. To create one:

1. Log into the Dokploy dashboard
2. Click your profile (top right) → **API Keys** (or **Profile Settings** → **API**)
3. Create a new token with full scope (or least privilege appropriate for your use)
4. Copy the token — you won't see it again

```bash
export DOKPLOY_TOKEN="your-token-here"
```

### Where to put them

Pick one, based on your workflow:

- **Shell rcfile** (`~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`) — available everywhere, including when running scripts by hand at a terminal.
- **Claude Code `settings.json`** — available only inside Claude sessions. Put under `"env"`:
  ```json
  {
    "env": {
      "DOKPLOY_URL": "https://dokploy.example.com",
      "DOKPLOY_TOKEN": "your-token-here"
    }
  }
  ```
- **`direnv` / `.envrc` per project** — if different projects target different Dokploy instances.

Shell rcfile is usually simplest. Do NOT commit tokens to git.

## Optional — SSH workflows

Required for deployment log tailing, Postgres restore, Traefik recovery.

```bash
export DOKPLOY_SSH_HOST="root@1.2.3.4"    # or a named host from ~/.ssh/config
```

If your VPS firewall blocks SSH by default (recommended), you'll need to whitelist your IP before connecting. Provider-specific — e.g. for Hetzner Cloud:

```bash
MY_IP=$(curl -4 -s ifconfig.me)
FW_NAME=$(hcloud firewall list -o noheader -o columns=name | head -1)
hcloud firewall add-rule "$FW_NAME" --direction in --source-ips "$MY_IP/32" \
  --port 22 --protocol tcp --description "Manual ssh access"
```

Consider automating this with a PreToolUse hook if you connect often.

## Optional — Postgres restore from object storage

Required by `scripts/restore-postgres.sh` for restoring from S3-compatible backup stores (Cloudflare R2, AWS S3, Backblaze B2, MinIO, etc).

```bash
export S3_ACCESS_KEY="..."
export S3_SECRET_KEY="..."
export S3_ENDPOINT="https://<account>.r2.cloudflarestorage.com"
export S3_PROVIDER="Cloudflare"   # or AWS, Minio, Other — see rclone docs
```

`rclone` must be installed on the VPS (not locally). One-time:

```bash
ssh "$DOKPLOY_SSH_HOST" "which rclone || curl -fsSL https://rclone.org/install.sh | bash"
```

## Verify setup

```bash
curl -sS "$DOKPLOY_URL/api/user.get" -H "x-api-key: $DOKPLOY_TOKEN" | jq .
```

Expected: JSON object with your user fields. If you get a 401, the token is wrong. If curl fails to connect, check `DOKPLOY_URL`.

## Typical workflow from zero

1. Set `DOKPLOY_URL` and `DOKPLOY_TOKEN` in your shell rcfile
2. Verify with the curl above
3. Ask Claude: "using my Dokploy, create a new project called `foo` and host my Next.js app from github.com/me/foo"
4. Claude reads `workflows.md`, asks clarifying questions it needs, and executes
