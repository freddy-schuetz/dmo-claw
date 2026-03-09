# dmo-claw — AI Agent for Tourism DMOs

A self-hosted AI agent for Destination Management Organizations (DMOs), built on [n8n-claw](https://github.com/freddy-schuetz/n8n-claw). Monitors Google Reviews, posts to Instagram, delivers alpine weather reports, manages tasks, and generates proactive briefings — all via OpenWebUI or any webhook-compatible chat interface.

First use case: **Tourismusverband Zugspitzregion** with role-based access for Marketing and Member Relations teams.

## Features

- **Google Reviews** — query locally cached reviews, rating summaries, automatic alerts on critical reviews (≤3 stars)
- **Instagram Posting** — create posts via Graph API, schedule posts for later, automatic token rotation
- **Alpine Weather** — snow depth, freezing level, 7-day forecast via Open-Meteo (free, no API key)
- **Role-based access** — write operations filtered from system prompt per role (not just instruction-based), admins see everything
- **Proactive notifications** — background workflows write to a notifications table; the agent loads unread alerts at conversation start and marks them read
- **Proactive briefings** — daily morning briefing (weather, reviews, posts, tasks) and weekly reports
- **Multi-user support** — conversation history, daily logs, and user profiles isolated per OpenWebUI email; shared long-term memory pool
- **Task management** — priorities, due dates, subtasks
- **Long-term memory** — remembers conversations with optional semantic search (RAG)
- **MCP Template Library** — install pre-built tools from [dmo-claw-templates](https://github.com/freddy-schuetz/dmo-claw-templates)
- **MCP Builder** — build new API integrations on demand via natural language
- **Web search** — self-hosted SearXNG instance (no API key needed)

## Architecture

```
OpenWebUI / Webhook (POST /webhook/dmo-claw)
  |
DMO Claw Agent (Claude Sonnet)
  |-- Task Manager        — create, track, complete tasks
  |-- Memory Save/Search  — long-term memory with vector search
  |-- MCP Client          — calls tools on MCP Servers (weather, reviews, Instagram)
  |-- MCP Builder         — creates new MCP Servers automatically
  |-- Library Manager     — install/remove templates from catalog
  |-- HTTP Tool           — simple web requests
  |-- Web Search          — SearXNG meta search
  +-- Self Modify         — inspect/list n8n workflows

Background Workflows:
  review-batch             — daily: fetch Google Reviews → local DB → notifications on ≤3 stars
  instagram-token-rotation — daily: check & refresh Instagram token
  post-scheduler           — every minute: publish scheduled posts
  morning-briefing         — daily 07:30: weather + reviews + posts + tasks summary
  weekly-report            — Friday 16:00: weekly aggregated report
  memory-consolidation     — daily 03:00: summarize conversations → long-term memory
  heartbeat                — every 15 min: proactive task reminders

Database:
  notifications            — proactive alerts from background workflows, loaded into agent prompt
```

## Stack

| Component | Purpose |
|---|---|
| [n8n](https://n8n.io) | Workflow automation engine |
| PostgreSQL | Database (reviews, users, tasks, memory) |
| [PostgREST](https://postgrest.org) | Auto-generated REST API |
| [Claude](https://anthropic.com) (Anthropic) | LLM powering the agent |
| [OpenWebUI](https://openwebui.com) | Chat interface (via Pipe Function) |
| [SearXNG](https://docs.searxng.org) | Self-hosted meta search engine |
| [Supabase Studio](https://supabase.com) | Database admin UI |

## Installation

### Prerequisites

- Linux VPS (Ubuntu 22.04+ or Debian 13, min. 2GB RAM)
- [Anthropic API Key](https://console.anthropic.com)
- Domain name (recommended for HTTPS)
- OpenWebUI instance (for chat interface)

### Quick Start

```bash
git clone https://github.com/freddy-schuetz/dmo-claw.git
cd dmo-claw
./setup.sh
```

The interactive setup configures everything: Docker services, database schema, n8n workflows, agent personality, DMO team members, and credentials.

### Connect OpenWebUI

1. Copy `docs/pipe-function.py` into OpenWebUI (Admin → Functions → New Pipe Function)
2. Set the Valves:
   - `N8N_WEBHOOK_URL`: Your n8n webhook URL (e.g. `https://your-domain/webhook/dmo-claw`)
   - `BEARER_TOKEN`: The webhook bearer token from your `.env`
3. Chat with the agent in OpenWebUI

### Add Credentials in n8n

After setup, open n8n and add credentials on nodes that need them:

| Credential | Name (exact) | Purpose |
|---|---|---|
| Postgres | `Supabase Postgres` | All database queries |
| Anthropic API | `Anthropic API` | Claude LLM |
| Header Auth | `DMO Claw Webhook Auth` | Webhook authentication |

## MCP Template Library

Install tourism-specific tools from the [dmo-claw-templates](https://github.com/freddy-schuetz/dmo-claw-templates) catalog:

| Template | Description | API Key |
|---|---|---|
| `weather-alpine` | Alpine weather, snow depth, freezing level, 7-day forecast | No (free) |
| `google-reviews` | Query locally cached Google Reviews | Google Places API Key |
| `instagram-post` | Create & schedule Instagram posts | Instagram Token + Account ID |

Ask your agent:
> "What templates are available?"
> "Install weather-alpine"

Templates requiring API keys will prompt you to enter the key via a secure one-time form link.

## Role-Based Access

DMO team members are configured during setup with roles:

| Role | Access | Example |
|---|---|---|
| `marketing` | Instagram, weather, reviews (read-only), tasks | Sandra (Marketing team) |
| `member_relations` | Reviews, member businesses (read-only), tasks | Thomas (Member Relations) |
| `admin` | All tools including member business write operations | Full access |
| `readonly` | Information only | View-only access |

Write operations (e.g. creating/editing member businesses) are enforced by filtering the corresponding `agents` DB entries out of the system prompt for non-admin roles — not by instruction-based restrictions. This prevents the LLM from bypassing access controls.

Roles are managed in the `dmo_users` table (keyed by OpenWebUI email).

## Customization

Edit the `soul` and `agents` tables in Supabase Studio to change agent personality, tool instructions, and behavior — no code changes needed.

DMO-specific soul entries: `organization_name`, `region`, `brand_hashtags`, `instagram_account`, `tone_of_voice`, `language`.

## Upstream

This project is a fork of [n8n-claw](https://github.com/freddy-schuetz/n8n-claw). To pull upstream improvements:

```bash
git fetch upstream
git merge upstream/main
```

## License

MIT
