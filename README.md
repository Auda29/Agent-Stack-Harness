# Agent Stack Harness (Windows Hybrid)

This harness is a **starter scaffold** for the stack:

- Multica
- agentchattr
- Claude Code
- Codex CLI
- SearXNG
- MemPalace

It is designed for a **Windows laptop** with a **hybrid setup**:

- **Docker** for infrastructure (`postgres`, `searxng`)
- **Local Windows processes** for agent-facing tools (`multica`, `agentchattr`, `claude`, `codex`, `mempalace`)

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

- Claude Code login
- Codex CLI login
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
- Claude Code
- Codex CLI

So this repo now uses a small Windows bootstrap script (`scripts/install-prereqs.ps1`) instead of pretending everything can be expressed as Python dependencies.

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
- Codex CLI

Optional:

```powershell
.\scripts\install-prereqs.ps1 -IncludeOptionalTools
```

Notes:
- `Claude Code` may still need manual installation depending on your machine / winget availability.
- You may need to open a **new PowerShell window** after installation so PATH updates are visible.

If you prefer, you can still install everything manually.

## 2) Run install

From PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1 -ProjectPath "C:\Path\To\Your\Project"
```

`-ProjectPath` is optional but useful.

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

## Expected URLs

- SearXNG: http://localhost:8888
- Multica frontend: http://localhost:3000
- Multica backend health: http://localhost:8080/health

## Notes about Multica

This harness creates `repos/multica/.env` from `config/multica.env.template`.
You still need to fill:

- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`

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

## Suggested next improvement

Once the stack works on your machine, the next sensible step is to add:

- a small **state file** for login/config completion
- better **process supervision**
- a **repo launcher** that opens your saved project path directly in a terminal/editor
