# Agent Stack Harness (Windows Hybrid)

This harness is a **starter scaffold** for the stack:

- Multica
- agentchattr
- pi-coding-agent
- SearXNG
- MemPalace

It is designed for a **Windows laptop** with a **hybrid setup**:

- **Docker** for infrastructure (`postgres`, `searxng`)
- **Local Windows processes** for agent-facing tools (`multica`, `agentchattr`, `pi`, `mempalace`)

## What this harness does

It gives you six scripts:

- `scripts/install-prereqs.ps1` — installs Windows prerequisites via `winget`
- `scripts/install.ps1` — first-time setup
- `scripts/onboarding.ps1` — guided manual steps
- `scripts/start.ps1` — starts the daily stack
- `scripts/stop.ps1` — stops harness-managed services
- `scripts/doctor.ps1` — diagnostics

These scripts are for stack lifecycle and bootstrap. They are not intended to be the primary runtime API for every stack component.

## Important limitations

This harness **cannot fully automate** these parts:

- pi login / provider authentication
- Multica Resend configuration
- Multica build edge cases on Windows
- MemPalace hook quirks on Windows

Those are the spots where you must still intervene manually.

## Dependency management note

A single `requirements.txt` is not enough for this repo because the prerequisites are not only Python packages. This harness depends on a mix of system tools and ecosystems:

- Docker Desktop
- Git
- Python
- Node.js / npm
- pnpm
- Go
- pi-coding-agent

So this repo uses a Windows bootstrap script (`scripts/install-prereqs.ps1`) instead of pretending everything can be expressed as Python dependencies.

## Configuration

Main config lives in `config/stack.json`.

That file is the source of truth for:

- Docker project name
- published infrastructure ports
- saved project path
- local URLs used by the harness
- cloned repo URLs

Current defaults:

- Postgres: `5432`
- SearXNG: `8888`
- Multica backend: `8080`
- Multica frontend: `3000`

Security note: the Docker Postgres service uses simple local development credentials (`multica` / `multica`). This harness is intended for localhost development only and is not production-ready as-is.

If you change ports in `config/stack.json`, the harness will sync them into:

- Docker Compose port bindings
- generated root `.env` for Compose
- `repos/multica/.env`
- Multica runtime environment variables used by `start.ps1`

## Recommended order

### 1) Install prerequisites

Recommended on Windows:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-prereqs.ps1
```

This installs the core prerequisites via `winget`:

- Docker Desktop
- Git
- Python 3.11+
- Node.js
- pnpm
- Go

Then it installs this agent CLI globally via npm:

- `@mariozechner/pi-coding-agent`

And it installs these default pi packages via `pi install`:

- `npm:pi-subagents`
- `npm:pi-searxng`
- `npm:pi-mcp-adapter`
- `npm:pi-lens`

Optional:

```powershell
.\scripts\install-prereqs.ps1 -IncludeOptionalTools
```

Notes:
- the script is safe to rerun; it skips tools that are already installed or already on `PATH`
- you may need to open a **new PowerShell window** after installation so PATH updates are visible
- pi authentication is still manual: run `pi`, then `/login`, or use provider API keys
- the prereq script also installs `pi-subagents`, `pi-searxng`, `pi-mcp-adapter`, and `pi-lens` by default

If you prefer, you can still install everything manually.

## 2) Run install

From PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1 -ProjectPath "C:\Path\To\Your\Project"
```

`-ProjectPath` is optional but useful.

Install does all of this:

- prepares local folders
- clones or updates the dependent repos
- creates or updates `repos/multica/.env`
- starts Docker infrastructure
- installs Python/Node dependencies
- attempts to build the Multica backend binary
- writes `~/.pi/searxng.json` for `pi-searxng`
- if `-ProjectPath` is provided, bootstraps `AGENTS.md`, `.pi/settings.json`, and `.pi/mcp.json` into that project repo

## 3) Run onboarding

```powershell
.\scripts\onboarding.ps1
```

Then complete the manual login/config steps.

If a project path was saved, onboarding also refreshes the starter `AGENTS.md`, `.pi/settings.json`, and `.pi/mcp.json` in that project.

## 4) Start the stack

```powershell
.\scripts\start.ps1
```

## 5) Diagnose problems

```powershell
.\scripts\doctor.ps1
```

## 6) Stop the stack

```powershell
.\scripts\stop.ps1
```

## URLs

The actual URLs come from `config/stack.json`.

Default values are:

- SearXNG: `http://localhost:8888`
- Multica frontend: `http://localhost:3000`
- Multica backend health: `http://localhost:8080/health`

The Docker-managed local SearXNG service is still kept in the stack. `pi-searxng` is intended to use that service, not replace it.

## Runtime interface model

Use the harness scripts for:

- installation
- onboarding
- start/stop
- health checks
- bootstrapping project guidance and Pi config like `AGENTS.md`, `.pi/settings.json`, and `.pi/mcp.json`

For actual agent work, prefer native runtime integrations:

- **SearXNG**: use `pi-searxng` first, otherwise the local HTTP endpoint
- **MemPalace**: prefer MCP/native memory integration
- **agentchattr**: use its native chat/runtime coordination loop
- **Multica**: interact through its configured frontend/backend services as needed

## Notes about pi-coding-agent

This harness assumes pi is your main coding-agent CLI.

Use pi like this after installation:

```powershell
pi
```

Then either:

- run `/login` and select a supported provider/subscription
- or configure provider API keys in your environment

Pi also supports RPC mode and an SDK, but this harness currently uses pi simply as the user-facing coding-agent CLI.

Pi automatically reads `AGENTS.md` files from the current directory and parent directories. This harness uses that behavior by bootstrapping a starter `AGENTS.md` into your saved project path.

The prereq installer also installs these pi packages by default:

- `pi-subagents`
- `pi-searxng`
- `pi-mcp-adapter`
- `pi-lens`

The install/onboarding flow also bootstraps Pi runtime config where possible:

- `~/.pi/searxng.json` for `pi-searxng`
- `.pi/settings.json` in the target project to mirror package dependencies
- `.pi/mcp.json` in the target project with a MemPalace MCP server entry

## Notes about Multica

This harness creates `repos/multica/.env` from `config/multica.env.template`.

Managed values are synced automatically by the harness:

- `DATABASE_URL`
- `FRONTEND_ORIGIN`
- `CORS_ALLOWED_ORIGINS`
- `PORT`
- `FRONTEND_PORT`

You still need to fill:

- `JWT_SECRET`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`

The install flow attempts to build the backend automatically, but depending on upstream Multica changes you may still need to build or adjust it manually on Windows.

## Notes about SearXNG

The local Docker-managed SearXNG service remains part of the stack.

`pi-searxng` is configured to use that local instance through `~/.pi/searxng.json`.

## Notes about MemPalace

MemPalace is installed in **editable mode from the cloned repo**:

```powershell
pip install -e .
```

That is intentional so you can inspect or patch issues more easily on Windows.

At runtime, MemPalace should ideally be used through its native MCP integration rather than through harness scripts.

If you pass `-ProjectPath`, the harness bootstraps `.pi/mcp.json` in that target project with a `mempalace` server entry using the harness-managed MemPalace virtualenv.

## Notes about agentchattr

agentchattr is started/managed by the harness, but the agent should use agentchattr through its own runtime coordination flow rather than treating the harness scripts as its main interface.

## Logs

Harness-managed process logs are written to:

- `data/logs/*.out.log`
- `data/logs/*.err.log`

PID metadata for managed local processes is written to:

- `data/pids/*.pid`

## Multi-clone note

Docker service detection now uses the configured Compose project name from `config/stack.json`.

To run multiple clones of this harness on the same machine more safely:

- give each clone a different `dockerProjectName`
- give each clone different published ports in `config/stack.json`

## CI

This repo includes a small GitHub Actions workflow that runs:

- PowerShell parse checks for all `scripts/**/*.ps1`
- `PSScriptAnalyzer` error checks
- a small config smoke check

## Suggested next improvement

Once the stack works on your machine, sensible next steps are:

- stronger process supervision / restart behavior
- deeper startup readiness checks
- a repo launcher that opens your saved project path directly in a terminal/editor
