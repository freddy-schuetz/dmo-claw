# CLAUDE.local.md — Local Dev Context
#
# Copy this file to CLAUDE.local.md and fill in your values.
# CLAUDE.local.md is gitignored — never commit it.
# This file (CLAUDE.local.example.md) is safe to commit as a template.

## Live n8n Instance

- **URL**: https://your-instance-url/
- **API Key**: stored in `.mcp.json` (N8N_API_KEY env var)

## SSH Access

SSH alias configured in `~/.ssh/config`.

```bash
ssh your-ssh-alias    # Login to server
docker logs -f n8n    # Follow n8n logs
```

## Operational Details

For full operational details (workflow IDs, credential IDs, server state, Docker stack),
read `docs/infrastructure.md` when needed — it is gitignored and local only.

Key operational data is also available in the auto-loaded MEMORY.md
(`~/.claude/projects/.../memory/MEMORY.md`).

## MCP Setup

`.mcp.json` (gitignored) configures n8n-mcp for direct live instance access via Claude Code.
Restart Claude Code after any changes to `.mcp.json`.

Available MCP tools:
- `n8n_create_workflow` / `n8n_update_partial_workflow` — build workflows on live instance
- `n8n_validate_workflow` / `n8n_autofix_workflow` — validate and fix
- `search_nodes` / `get_node` — find and inspect node types
