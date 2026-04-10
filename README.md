# Agent Stack Harness (Pi-first on Windows)

This harness is a **Pi-first starter scaffold** for local agent work on Windows.

Core stack:

- pi-coding-agent
- SearXNG
- MemPalace
- agentchattr

Optional:

- Multica

Runtime model:

- **Docker** for infrastructure (`postgres`, `searxng`)
- **Local Windows processes** for agent-facing tools (`pi`, `mempalace`, `agentchattr`)

## Quickstart

Fastest path:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\quickinstall.ps1 -ProjectPath "C:\Path\To\Your\Project"
```

Then:

- open your target project folder
- run `pi`
- run `/login`
- for non-trivial work, prefer `@tintinweb/pi-tasks` to track steps and progress inside Pi

Manual flow:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-prereqs.ps1
.\scripts\install.ps1 -ProjectPath "C:\Path\To\Your\Project"
.\scripts\onboarding.ps1
.\scripts\start.ps1
```

Optional Multica flow:

```powershell
.\scripts\quickinstall.ps1 -ProjectPath "C:\Path\To\Your\Project" -IncludeMultica
```

## What this harness does

Core scripts:

- `quickinstall.ps1` — one-shot setup
- `install-prereqs.ps1` — prerequisites
- `install.ps1` — install/bootstrap
- `onboarding.ps1` — refresh config + next steps
- `start.ps1` / `stop.ps1` — daily lifecycle
- `doctor.ps1` — diagnostics

By default, the flow is Pi-first. Multica is only included with `-IncludeMultica`.

## Important limitations

This harness **cannot fully automate** these parts:

- pi login / provider authentication
- MemPalace hook quirks on Windows
- Multica login/build edge cases if you explicitly enable Multica

Those are the places where manual intervention may still be needed.

## Dependency management note

This repo depends on system tools across multiple ecosystems, so a single `requirements.txt` would not be enough. Use `scripts/install-prereqs.ps1` for bootstrap.

## Configuration

Main config lives in `config/stack.json`.

That file is the source of truth for:

- Docker project name
- published infrastructure ports
- saved project path
- local URLs used by the harness
- cloned repo URLs

Current core defaults:

- Postgres: `5432`
- SearXNG: `8888`

Optional Multica defaults:

- Multica backend: `8080`
- Multica frontend: `3000`

Security note: the Docker Postgres service uses simple local development credentials (`multica` / `multica`). This harness is intended for localhost development only and is not production-ready as-is.

If you change ports in `config/stack.json`, the harness will sync them into:

- Docker Compose port bindings
- generated root `.env` for Compose
- `repos/multica/.env` when Multica is enabled
- Multica runtime environment variables used by `start.ps1` when Multica is enabled

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

It also installs useful optional developer tooling commonly needed by Pi packages and optional Multica support:

- pnpm
- Go

Then it installs this agent CLI globally via npm:

- `@mariozechner/pi-coding-agent`

And it installs these default Pi packages via `pi install`:

- `npm:@tintinweb/pi-tasks` — structured multi-step task tracking inside Pi
- `npm:pi-subagents` — delegation and isolated-context helper flows
- `npm:pi-searxng` — Pi-native search against the local SearXNG instance
- `npm:pi-mcp-adapter` — MCP-backed tool integration when needed
- `npm:pi-lens` — extra inspection/context tooling

Optional:

```powershell
.\scripts\install-prereqs.ps1 -IncludeOptionalTools
```

Notes:
- safe to rerun
- open a **new PowerShell window** if PATH changes are not visible yet
- pi authentication is still manual: run `pi`, then `/login`

## 2) Run install

From PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1 -ProjectPath "C:\Path\To\Your\Project"
```

`-ProjectPath` is optional but useful.

Install does all of this:

- prepares local folders
- clones or updates the dependent repos needed for the selected flow
- starts Docker infrastructure
- installs Python/Node dependencies for the non-Multica tools
- writes `~/.pi/searxng.json` for `pi-searxng`
- if `-ProjectPath` is provided, bootstraps `AGENTS.md`, `.pi/settings.json`, and `.pi/mcp.json` into that project repo
- if `-IncludeMultica` is passed, also clones/updates `repos/multica`, creates `repos/multica/.env`, installs Multica dependencies, builds Multica, and runs Multica migrations

## 3) Run onboarding

```powershell
.\scripts\onboarding.ps1
```

Then complete the manual login/config steps.

If a project path was saved, onboarding also refreshes the starter `AGENTS.md`, `.pi/settings.json`, and `.pi/mcp.json` in that project.

If you want Multica onboarding too, run:

```powershell
.\scripts\onboarding.ps1 -IncludeMultica
```

## 4) Start the stack

```powershell
.\scripts\start.ps1
```

This starts the Pi-first local stack.

If you also want Multica services and daemon startup, run:

```powershell
.\scripts\start.ps1 -IncludeMultica
```

## 5) Diagnose problems

```powershell
.\scripts\doctor.ps1
```

To include Multica diagnostics too:

```powershell
.\scripts\doctor.ps1 -IncludeMultica
```

If Docker image pulls fail with authentication errors, try:

```powershell
docker logout
docker login
docker pull searxng/searxng:latest
docker pull pgvector/pgvector:pg17
```

## 6) Stop the stack

```powershell
.\scripts\stop.ps1
```

To also stop Multica processes/daemon:

```powershell
.\scripts\stop.ps1 -IncludeMultica
```

## URLs

Actual URLs come from `config/stack.json`.

Core default:

- SearXNG: `http://localhost:8888`

Optional Multica defaults:

- frontend: `http://localhost:3000`
- backend health: `http://localhost:8080/health`

## Runtime model

Use the harness scripts for setup, lifecycle, diagnostics, and project bootstrap.

For actual agent work, prefer native runtime integrations:

- **Tasks**: `@tintinweb/pi-tasks` for structured multi-step work and progress tracking
- **SearXNG**: `pi-searxng` first, otherwise the local HTTP endpoint
- **MemPalace**: MCP/native integration
- **agentchattr**: its own runtime coordination flow
- **Multica**: only if you explicitly enabled it

## Notes about pi-coding-agent

This harness assumes `pi` is your main coding-agent CLI.

After installation:

```powershell
pi
```

Then run `/login` or configure provider API keys.

The harness also bootstraps:

- `AGENTS.md`
- `~/.pi/searxng.json`
- project `.pi/settings.json`
- project `.pi/mcp.json`

Project `.pi/settings.json` mirrors the default package set, including `@tintinweb/pi-tasks`, so project-local Pi startup picks up the same core workflow packages.

## Notes about Multica (optional)

Multica is no longer part of the default flow.

Only when you pass `-IncludeMultica`, the harness will:

- clone/update `repos/multica`
- create `repos/multica/.env` from `config/multica.env.template`
- install dependencies
- build the backend
- run migrations
- include Multica onboarding/start/stop/doctor steps

If you enable it, you still need to fill values like:

- `JWT_SECRET`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`

Without `RESEND_API_KEY`, Multica prints local dev verification codes into backend logs instead of sending email.

## Notes about SearXNG

The local Docker-managed SearXNG service remains part of the stack, and `pi-searxng` is configured to use it through `~/.pi/searxng.json`.

## Notes about MemPalace

MemPalace is installed in **editable mode from the cloned repo**:

```powershell
pip install -e .
```

That is intentional so you can inspect or patch issues more easily on Windows.

At runtime, MemPalace should ideally be used through its native MCP integration rather than through harness scripts.

If you pass `-ProjectPath`, the harness bootstraps `.pi/mcp.json` in that target project with a `mempalace` server entry using the harness-managed MemPalace virtualenv.

## Notes about pi-tasks

`@tintinweb/pi-tasks` is included in the default Pi package set and should be treated as the default task-management layer for longer Pi sessions.

Use it for:

- multi-step implementation work
- explicit task lists and dependencies
- progress tracking across longer sessions
- coordinating subtasks or subagents when needed

For very small one-shot edits, do not force unnecessary task overhead.

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
