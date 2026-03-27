# dmo-claw — AI Agent for Tourism DMOs

A self-hosted AI agent for Destination Management Organizations (DMOs), built on [n8n-claw](https://github.com/freddy-schuetz/n8n-claw). Monitors Google Reviews, posts to Instagram, delivers alpine weather reports, manages tasks and reminders, delegates to expert agents, and generates proactive briefings — all via OpenWebUI or any webhook-compatible chat interface.

Includes a demo configuration for a fictional **Tourismusverband Zugspitzregion** — showing how a DMO could use the agent with role-based access for Marketing and Member Relations teams.

## Contents

- [What it does](#what-it-does)
- [Architecture](#architecture)
- [Installation](#installation)
- [Services & URLs](#services--urls)
- [MCP Skills Library](#mcp-skills-library)
- [Expert Agents](#expert-agents)
- [Role-Based Access](#role-based-access)
- [Memory](#memory)
- [Reminders & Scheduled Actions](#reminders--scheduled-actions)
- [Heartbeat & Background Checks](#heartbeat--background-checks)
- [Customization](#customization)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Upstream](#upstream)
- [Stack](#stack)

---

## What it does

Talk to your DMO agent in natural language — it manages reviews, social media, tasks, reminders, and proactively keeps your team on track.

- **Google Reviews** — query locally cached reviews, rating summaries, automatic alerts on critical reviews (≤3 stars)
- **Instagram Posting** — create posts via Graph API, schedule posts for later, automatic token rotation
- **Alpine Weather** — snow depth, freezing level, 7-day forecast via Open-Meteo (free, no API key)
- **Expert agents** — delegate complex tasks to specialized sub-agents (research, content creation, data analysis)
- **Smart reminders** — timed reminders ("remind me in 2 hours to...")
- **Scheduled actions** — the agent executes instructions at a set time ("check reviews at 9am")
- **Recurring actions** — repeating tasks on any schedule ("daily briefing at 8am", "check emails every 15 minutes")
- **Smart background checks** — monitoring tasks only notify you when something new is found
- **Proactive notifications** — background workflows write to a notifications table; the agent loads unread alerts at conversation start
- **Proactive briefings** — daily morning briefing (weather, reviews, posts, tasks) and weekly reports
- **Long-term memory** — remembers conversations with optional semantic search (RAG)
- **Task management** — priorities, due dates, subtasks
- **Role-based access** — write operations filtered from system prompt per role (not just instruction-based)
- **Multi-user support** — conversation history, daily logs, and user profiles isolated per OpenWebUI email
- **MCP Skills Library** — install pre-built tools from [dmo-claw-templates](https://github.com/freddy-schuetz/dmo-claw-templates)
- **MCP Builder** — build new API integrations on demand via natural language
- **Web search** — self-hosted SearXNG instance (no API key needed)
- **Web reader** — reads webpages as clean markdown via Crawl4AI (JS rendering, no boilerplate)
- **Email bridge** — read and send emails via IMAP/SMTP (stateless REST microservice)
- **Extensible** — add new skills and capabilities through natural language or from the skill catalog

## Architecture

```
OpenWebUI / Webhook (POST /webhook/dmo-claw)
  │
DMO Claw Agent (Claude Sonnet)
  ├── Task Manager        — create, track, complete tasks
  ├── Memory Save/Search  — long-term memory with vector search
  ├── MCP Client          → calls tools on MCP Servers (weather, reviews, Instagram)
  ├── MCP Builder         → creates new MCP Servers automatically
  ├── Library Manager     → install/remove skills from catalog
  ├── Reminder            — timed reminders + scheduled actions
  ├── Expert Agent        → delegates to specialized sub-agents
  ├── Agent Library       → install/remove expert agents from catalog
  ├── HTTP Tool           — simple web requests
  ├── Web Search          — search the web (SearXNG)
  ├── Web Reader          — read webpages as markdown (Crawl4AI)
  └── Self Modify         — inspect/list n8n workflows

Background Workflows (automated):
  💓 Heartbeat              — every 5 min: recurring actions + proactive reminders
  🔍 Background Checker     — silent checks: only notifies when something new is found
  ⏰ Reminder Runner         — every 1 min: sends due reminders + triggers one-time actions
  🧠 Memory Consolidation   — daily 03:00: summarizes conversations → long-term memory
  ☀️ Morning Briefing        — daily 07:30: weather + reviews + posts + tasks summary
  📊 Weekly Report           — Friday 16:00: weekly aggregated report
  📥 Review Batch Import     — daily: fetch Google Reviews → local DB → notifications on ≤3 stars
  🔄 Instagram Token Rotation — daily: check & refresh Instagram token
  📤 Post Scheduler          — every minute: publish scheduled Instagram posts
```

## Stack

| Component | Purpose |
|---|---|
| [n8n](https://n8n.io) | Workflow automation engine |
| PostgreSQL | Database (reviews, users, tasks, memory, reminders) |
| [PostgREST](https://postgrest.org) | Auto-generated REST API (Docker-internal only) |
| [Claude](https://anthropic.com) (Anthropic) | LLM powering the agent |
| [OpenWebUI](https://openwebui.com) | Chat interface (via Pipe Function) |
| [SearXNG](https://docs.searxng.org) | Self-hosted meta search engine |
| [Crawl4AI](https://github.com/unclecode/crawl4ai) | Self-hosted web crawler (JS rendering, clean markdown) |
| [Supabase Studio](https://supabase.com) | Database admin UI |
| [Kong](https://konghq.com) | API gateway (Docker-internal only) |

---

## Installation

### What you need

- A Linux VPS (Ubuntu 22.04+ or Debian 13, min. 4GB RAM)
- An **Anthropic API Key** — from [console.anthropic.com](https://console.anthropic.com)
- A **domain name** (recommended for HTTPS)
- An **OpenWebUI instance** (for chat interface)

### Step 1 — Clone & run

```bash
git clone https://github.com/freddy-schuetz/dmo-claw.git && cd dmo-claw && ./setup.sh
```

The script will:

1. **Update the system** (`apt update && apt upgrade`)
2. **Install Docker** automatically if not present
3. **Start n8n** so you can generate an API key
4. **Ask you for configuration** interactively:
   - n8n API Key *(generated in n8n UI → Settings → API)*
   - Anthropic API Key
   - Domain name *(optional — enables HTTPS via Let's Encrypt + nginx)*
5. **Configure your agent's personality**:
   - Agent name, your name, preferred language, timezone
   - Communication style (casual / professional / friendly)
   - Free-text custom persona *(overrides the above)*
6. **Configure DMO settings**:
   - Organization name, region, brand hashtags, Instagram account
7. **Set up DMO team members** with roles (marketing, member_relations, admin)
8. **Configure embeddings** for semantic memory search (optional)
9. **Start all services** (n8n, PostgreSQL, PostgREST, Kong, SearXNG, Crawl4AI)
10. **Apply database schema** and seed data
11. **Create n8n credentials** (Anthropic, Webhook Auth, Postgres)
12. **Import all workflows** into n8n
13. **Wire workflow references** and activate the agent

### Step 2 — Connect OpenWebUI

1. Copy `docs/pipe-function.py` into OpenWebUI (Admin → Functions → New Pipe Function)
2. Set the Valves:
   - `N8N_WEBHOOK_URL`: Your n8n webhook URL (e.g. `https://your-domain/webhook/dmo-claw`)
   - `BEARER_TOKEN`: The webhook bearer token from setup output
3. Chat with the agent in OpenWebUI

### Step 3 — Add credentials in n8n UI

Open n8n at the URL shown at the end of setup.

The easiest way is to open each workflow and click **"Create new credential"** directly on the node that needs it. n8n will prompt you automatically.

**Credentials you'll need:**

| Credential | Name (exact!) | Where needed |
|---|---|---|
| Postgres | `Supabase Postgres` | Agent, Sub-Agent Runner |
| Anthropic API | `Anthropic API` | Agent (Claude node), MCP Builder, Sub-Agent Runner |
| Header Auth | `DMO Claw Webhook Auth` | Agent (Webhook Trigger) — *created automatically by setup* |

**Postgres connection details** *(shown in setup output)*:
- Host: `db` | Port: `5432` | DB: `postgres` | User: `postgres`
- Password: *(shown at end of setup)*
- SSL: `disable`

**Optional: Embeddings for semantic memory search:**

During setup, you'll be asked for an embedding API key. This enables vector-based memory search (RAG).

- **OpenAI** (default): `text-embedding-3-small` — [platform.openai.com](https://platform.openai.com) (requires API key)
- **Voyage AI**: `voyage-3-lite` — [voyageai.com](https://www.voyageai.com) (free tier available)
- **Ollama**: `nomic-embed-text` — local, no API key needed (requires Ollama running on your server)

Without an embedding key, the agent still works — it falls back to keyword-based memory search.

### Step 4 — Activate remaining workflows

These workflows are **activated automatically** by setup:

| Workflow | Purpose |
|---|---|
| DMO Claw Agent | Main agent — receives OpenWebUI + Webhook messages, calls tools |
| Heartbeat | Background: recurring actions + proactive reminders (every 5 min) |
| Background Checker | Sub-workflow: silent background checks, only notifies on changes |
| Memory Consolidation | Background: summarizes conversations into long-term memory (daily 3am) |
| Reminder Runner | Background: delivers reminders + triggers one-time actions (every 1 min) |
| Credential Form | Secure one-time forms for entering API keys |

These workflows need to be **activated manually** in n8n UI (if you use them):

| Workflow | Purpose |
|---|---|
| Review Batch Import | Daily Google Reviews import |
| Post Scheduler | Scheduled Instagram posts |
| Morning Briefing | Daily summary at 07:30 |
| Weekly Report | Friday 16:00 aggregated report |
| Instagram Token Rotation | Auto-refresh Instagram token |
| MCP Builder | Build custom MCP skills on demand |
| MCP: Weather | Example MCP Server — weather via Open-Meteo (no API key) |

Sub-workflows (called by other workflows, no manual activation needed):

| Workflow | Called by |
|---|---|
| MCP Client | Agent — calls tools on MCP skill servers |
| MCP Library Manager | Agent — installs/removes skills from catalog |
| Sub-Agent Runner | Agent — runs expert agents with loaded personas |
| Agent Library Manager | Agent — installs/removes expert agents |
| ReminderFactory | Agent — saves reminders/tasks to database |
| Credential Form | Library Manager — secure form for entering API keys |

### Step 5 — Start chatting

Send a message in OpenWebUI. The agent is ready!

---

<details>
<summary>

## Services & URLs

</summary>

After setup, these services run:

| Service | URL | Purpose |
|---|---|---|
| n8n | `https://YOUR-DOMAIN` | Workflow editor |
| Supabase Studio | `http://localhost:3001` (via SSH tunnel) | Database admin UI |
| Webhook API | `https://YOUR-DOMAIN/webhook/dmo-claw` | Agent HTTP endpoint (POST, requires X-API-Key header) |
| PostgREST API | `http://kong:8000` (Docker-internal only) | REST API for PostgreSQL |

### Accessing Supabase Studio

Supabase Studio is bound to `localhost` only (not publicly exposed). To access it from your browser, open an SSH tunnel:

```bash
ssh -L 3001:localhost:3001 user@YOUR-VPS-IP
```

Then open `http://localhost:3001` in your browser.

</details>

---

<details>
<summary>

## MCP Skills Library

</summary>

Install pre-built skills from the [dmo-claw-templates](https://github.com/freddy-schuetz/dmo-claw-templates) catalog — no coding required. Just ask your agent:

> "What skills are available?"
> "Install weather-alpine"
> "Remove weather-alpine"

The Library Manager fetches skill templates from GitHub, imports the workflows into n8n, and registers the new MCP server automatically.

> After installing a skill: **deactivate → reactivate** the new MCP workflow in n8n UI (required due to a webhook registration bug in n8n).

**Available skills:**

| Skill | Category | Description | API Key |
|---|---|---|---|
| Alpine Weather | Productivity | Snow depth, freezing level, 7-day forecast | No (free) |
| Google Reviews | Tourism | Query locally cached Google Reviews | Google Places API Key |
| Instagram Post | Social Media | Create & schedule Instagram posts | Instagram Token + Account ID |

See the full catalog at [dmo-claw-templates](https://github.com/freddy-schuetz/dmo-claw-templates).

**Skills with API keys:** Some skills require an API key. When you install one, the agent sends you a secure one-time link. Click it, enter your key — done. The key is stored in the database and the skill reads it at runtime. Links expire after 10 minutes and can only be used once.

> **Security notice — Skill credentials are stored in plain text**
>
> API keys entered via the credential form are currently stored **unencrypted** in the `template_credentials` table in PostgreSQL. This means anyone with database access can read them.
>
> **Mitigation:** Neither the database nor the API are reachable from the internet. PostgREST runs on a Docker-internal network only, and PostgreSQL (port 5432) is bound to `127.0.0.1`. To read credentials, an attacker would need SSH access to your VPS. Secure SSH access (key-based auth, no root password, fail2ban).

Want to build a custom skill instead? Ask your agent:

> "Build me an MCP server for the OpenLibrary API — look up books by ISBN"

The MCP Builder will search for API docs, generate code, deploy two workflows, and register the tool automatically.

</details>

---

<details>
<summary>

## Expert Agents

</summary>

Delegate complex tasks to specialized sub-agents. Each expert has its own AI agent with a focused persona, tools (web search, HTTP requests, web reader, MCP), and works independently — then the main agent rephrases the result in its own tone.

**Three experts are included by default:**

| Agent | Speciality |
|---|---|
| Research Expert | Web research, fact-checking, source evaluation, structured summaries |
| Content Creator | Copywriting, social media posts, blog articles, marketing copy |
| Data Analyst | Data analysis, pattern recognition, KPI interpretation, structured reports |

**Using expert agents:**

> "Research the best hiking trails in Tyrol with sources"
> "Write an Instagram post about our new product launch"
> "Analyze these numbers and give me a summary"

The agent automatically picks the right expert based on your request — or you can ask explicitly:

> "Let the research expert look into this"
> "Delegate this to the content creator"

**Managing agents:**

> "What expert agents do I have?"
> "Install the data analyst"
> "Remove the content creator"

Install more experts from the [agent catalog](https://github.com/freddy-schuetz/n8n-claw-agents) or ask the community to contribute new ones.

</details>

---

<details>
<summary>

## Role-Based Access

</summary>

DMO team members are configured during setup with roles:

| Role | Access | Example |
|---|---|---|
| `marketing` | Instagram, weather, reviews (read-only), tasks | e.g. marketing team members |
| `member_relations` | Reviews, member businesses (read-only), tasks | e.g. member relations staff |
| `admin` | All tools including member business write operations | Full access |
| `readonly` | Information only | View-only access |

Write operations (e.g. creating/editing member businesses) are enforced by filtering the corresponding `agents` DB entries out of the system prompt for non-admin roles — not by instruction-based restrictions. This prevents the LLM from bypassing access controls.

Roles are managed in the `dmo_users` table (keyed by OpenWebUI email).

</details>

---

<details>
<summary>

## Memory

</summary>

The agent has a multi-layered memory system — it remembers things you tell it and learns from your conversations over time.

**Automatic memory:** The agent decides on its own what's worth remembering from your conversations (preferences, facts, decisions). No action needed.

**Manual memory:** You can also explicitly ask it to remember something:

> "Remember that the summit restaurant opens at 10am on weekdays"

**Memory search:** When relevant, the agent searches its memory to give you contextual answers. With an embedding API key (configured during setup), it uses semantic search — finding memories by meaning, not just keywords.

**Memory Consolidation** runs automatically every night at 3am. It summarizes the day's conversations into concise long-term memories with vector embeddings. Requires an embedding API key (OpenAI, Voyage AI, or Ollama — configured during setup).

</details>

---

<details>
<summary>

## Reminders & Scheduled Actions

</summary>

The agent supports three types of timed actions:

**Reminders** — sends a message at the specified time:

> "Remind me in 30 minutes to check the review responses"
> "Remind me tomorrow at 9am about the Instagram post"

**Scheduled Actions** — the agent actively executes instructions at the specified time and sends the result:

> "Check the latest Google Reviews at 9am and summarize them"
> "Search for news about our region tomorrow at 7am"

**Recurring Actions** — repeating scheduled actions on an interval, daily, or weekly schedule:

> "Check my emails every 15 minutes"
> "Give me a daily briefing every morning at 8am"
> "Every Monday and Friday at 9am, summarize the latest tourism news"

Recurring actions are managed via natural language — list, pause, resume, or delete them:

> "Show my scheduled actions"
> "Pause the email check"
> "Delete action 2"

Reminders and one-time scheduled actions are delivered by the **Reminder Runner** (polls every minute). Recurring actions are executed by the **Heartbeat** (runs every 5 minutes).

</details>

---

<details>
<summary>

## Heartbeat & Background Checks

</summary>

The Heartbeat is a background workflow that runs every 5 minutes. It executes recurring scheduled actions and delivers proactive reminders.

### Recurring Actions

When you create a recurring action, the agent decides how it should notify you:

- **`always`** — always sends the result (e.g. morning briefings, reports). The main agent executes the task with full personality, conversation history, and all tools.
- **`on_change`** — only notifies when something new is found (e.g. email monitoring, review tracking). A lightweight **Background Checker** executes the task silently and only sends a notification when there's actually something to report.

The agent picks the right mode automatically based on your request:

> "Give me a daily briefing at 8am" → `always` (you always want the briefing)
> "Check for new reviews every hour" → `on_change` (only notify on new reviews)

### How it works

```
Heartbeat (every 5 min)
  → Load due actions from DB
  → For each action, check notify_mode:

    'always' (e.g. briefing):
      → Main Agent executes task → always sends notification

    'on_change' (e.g. review check):
      → Background Checker executes task
      → Something new? → sends notification
      → Nothing new?   → stays silent
```

The Background Checker is a lightweight sub-workflow with Claude + tools (MCP skills, web search, HTTP requests, web reader) but without personality or conversation history — fast and cost-efficient.

### Proactive Reminders

The Heartbeat also checks for overdue or urgent tasks and sends a short reminder — without you having to ask.

> "Enable the heartbeat" / "Disable proactive messages"

Rate-limited to one message every 2 hours (configurable) — no spam.

</details>

---

<details>
<summary>

## Customization

</summary>

Edit the `soul` and `agents` tables directly in Supabase Studio (`http://localhost:3001` via [SSH tunnel](#accessing-supabase-studio)) to change your agent's personality, tools, and behavior — no code changes needed.

**DMO-specific soul entries:** `organization_name`, `region`, `brand_hashtags`, `instagram_account`, `tone_of_voice`, `language`.

| Table | Contents |
|---|---|
| `soul` | Agent personality (name, persona, vibe, boundaries) — loaded into system prompt |
| `agents` | Tool instructions, MCP config, memory behavior — loaded into system prompt |
| `user_profiles` | User name, timezone, preferences (language, morning briefing) |
| `dmo_users` | DMO team members with roles (keyed by OpenWebUI email) |
| `tasks` | Task management (title, status, priority, due date, subtasks) |
| `reminders` | Scheduled reminders + one-time tasks (message, time, type, delivery status) |
| `scheduled_actions` | Recurring actions (schedule, instruction, notify_mode, next_run) |
| `heartbeat_config` | Heartbeat + morning briefing settings (enabled, last_run, intervals) |
| `notifications` | Proactive alerts from background workflows |
| `tools_config` | API keys for Anthropic, embedding provider — used by Heartbeat + Consolidation |
| `mcp_registry` | Available MCP servers (name, URL, tools) |
| `template_credentials` | API keys for MCP templates (entered via credential form) |
| `conversations` | Full chat history (session-based) |
| `memory_long` | Long-term memory with vector embeddings (semantic search) |
| `memory_daily` | Daily interaction log (used by Memory Consolidation) |

</details>

---

<details>
<summary>

## Updating

</summary>

**Normal update** — pulls code + Docker images, restarts services. Your personality, credentials, and data are preserved:

```bash
cd dmo-claw && ./setup.sh
```

**Full reconfigure** — reimports all workflows and optionally re-runs configuration sections. Each section can be skipped individually:

```bash
./setup.sh --force
```

With `--force` on an existing installation, setup asks per block:

```
Change personality settings? (y/N):
Change DMO configuration? (y/N):
Change DMO users? (y/N):
Change embedding/RAG settings? (y/N):
```

Press Enter to keep current settings, or `y` to reconfigure that section. This lets you reimport workflows without re-entering all configuration.

</details>

---

<details>
<summary>

## Troubleshooting

</summary>

**Agent not responding?**
→ Check all workflows are **activated** in n8n UI

**"Credential does not exist" error?**
→ Add the Postgres/Anthropic credential manually in n8n (see Step 3)

**MCP Builder fails?**
→ Make sure the LLM node in MCP Builder has Anthropic API selected

**Agent shows wrong time?**
→ Re-run `./setup.sh --force` and change personality settings, or update directly in `user_profiles` table via Supabase Studio

**Heartbeat not sending messages?**
→ Check that `heartbeat_config` has `enabled = true`. Enable via chat: *"Enable the heartbeat"*

**Memory search returns nothing?**
→ Check your embedding API key in the `tools_config` table (tool_name: `embedding`). Without a valid key, memory falls back to keyword search.

**Logs:**
```bash
docker logs dmo-claw          # n8n
docker logs dmo-claw-db       # PostgreSQL
docker logs dmo-claw-rest     # PostgREST
```

</details>

---

## Upstream

This project is a fork of [n8n-claw](https://github.com/freddy-schuetz/n8n-claw). To pull upstream improvements:

```bash
git remote add upstream https://github.com/freddy-schuetz/n8n-claw.git
git fetch upstream
git merge upstream/main
```

---

## License

MIT
