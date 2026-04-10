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
- the prereq script also installs `pi-subagents`, `pi-mcp-adapter`, and `pi-lens` by default

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

## 3) Run onboarding

```powershell
.\scripts\onboarding.ps1
```

Then complete the manual login/config steps.

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

The prereq installer also installs these pi packages by default:

- `pi-subagents`
- `pi-mcp-adapter`
- `pi-lens`

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

## Notes about MemPalace

MemPalace is installed in **editable mode from the cloned repo**:

```powershell
pip install -e .
```

That is intentional so you can inspect or patch issues more easily on Windows.

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
