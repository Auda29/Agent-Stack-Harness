param(
    [switch]$IncludeMultica
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/env.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/mempalace.ps1')

$config = Get-StackConfig
Write-Section 'Onboarding checklist'

Write-Section 'pi runtime config'
Initialize-PiSearxngConfig

if ($config.projectPath) {
    Write-Section 'Project pi bootstrap'
    Initialize-ProjectPiSettings -ProjectPath $config.projectPath
    Initialize-ProjectMcpConfig -ProjectPath $config.projectPath
    Initialize-ProjectAgentsMd -ProjectPath $config.projectPath

    Write-Section 'MemPalace project initialization'
    Initialize-MemPalaceProject -ProjectPath $config.projectPath
    if (Test-MemPalaceStatus) {
        Write-Good 'MemPalace status check passed'
    } else {
        Write-Warn 'MemPalace status check failed'
    }
}

if (Test-DockerServiceRunning 'postgres') { Write-Good 'Postgres container is running' } else { Write-Warn 'Postgres container is not running' }
if (Test-DockerServiceRunning 'searxng') { Write-Good 'SearXNG container is running' } else { Write-Warn 'SearXNG container is not running' }
if (Test-HttpOk $config.urls.searxng) { Write-Good "SearXNG reachable at $($config.urls.searxng)" } else { Write-Warn 'SearXNG not reachable yet' }

if ($IncludeMultica) {
    $multicaEnv = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
    if (Test-Path $multicaEnv) {
        Write-Info "Open this file and fill RESEND_API_KEY + RESEND_FROM_EMAIL:`n$multicaEnv"
    } else {
        Write-Warn 'Multica .env missing'
    }

    if (-not (Test-MulticaEnvComplete)) {
        Write-Warn 'Multica .env is incomplete. Without RESEND_API_KEY, login codes are not emailed; they are printed to the Multica backend log instead.'
        Write-Info "Check backend logs for a dev login code in:`n$(Join-Path (Get-HarnessRoot) 'data/logs')"
    } else {
        Write-Good 'Multica .env looks complete'
    }

    Write-Section 'Multica CLI login'
    Invoke-MulticaCliLogin
} else {
    Write-Info 'Skipping Multica onboarding steps (use -IncludeMultica to enable)'
}

Write-Info 'Next manual actions:'
Write-Host '  1) Start pi: run `pi`' -ForegroundColor White
Write-Host '  2) Inside pi, run `/login` and select your provider, or configure provider API keys' -ForegroundColor White
Write-Host '  3) Restart pi after package/config changes so pi-searxng and pi-mcp-adapter pick them up' -ForegroundColor White
Write-Host '  4) Review and customize the generated AGENTS.md and .pi config files in your project repo if needed' -ForegroundColor White
if ($config.projectPath) {
    Write-Host "  5) Recommended next MemPalace step: mempalace mine `"$($config.projectPath)`"" -ForegroundColor White
    Write-Host '     Use this when you want MemPalace to ingest the project files into memory.' -ForegroundColor DarkGray
    Write-Host '  6) Then run start.ps1' -ForegroundColor White
} else {
    Write-Host '  5) Then run start.ps1' -ForegroundColor White
}
if ($IncludeMultica) {
    Write-Host '  7) Multica runtimes appear only after the Multica daemon is running; if none appear, check whether `multica daemon start` succeeded on your machine' -ForegroundColor White
}
