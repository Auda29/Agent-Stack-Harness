. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/env.ps1')

$config = Get-StackConfig
Write-Section 'Onboarding checklist'

if (Test-DockerServiceRunning 'postgres') { Write-Good 'Postgres container is running' } else { Write-Warn 'Postgres container is not running' }
if (Test-DockerServiceRunning 'searxng') { Write-Good 'SearXNG container is running' } else { Write-Warn 'SearXNG container is not running' }
if (Test-HttpOk $config.urls.searxng) { Write-Good "SearXNG reachable at $($config.urls.searxng)" } else { Write-Warn 'SearXNG not reachable yet' }

$multicaEnv = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
if (Test-Path $multicaEnv) {
    Write-Info "Open this file and fill RESEND_API_KEY + RESEND_FROM_EMAIL:`n$multicaEnv"
} else {
    Write-Warn 'Multica .env missing'
}

if (-not (Test-MulticaEnvComplete)) {
    Write-Warn 'Multica .env is incomplete. Fill the Resend settings before login.'
} else {
    Write-Good 'Multica .env looks complete'
}

Write-Info 'Next manual actions:'
Write-Host '  1) Log into Claude Code: run `claude` once' -ForegroundColor White
Write-Host '  2) Log into Codex CLI: run `codex` once' -ForegroundColor White
Write-Host '  3) Verify Multica build succeeded during install; rebuild manually only if needed' -ForegroundColor White
Write-Host '  4) Then run start.ps1' -ForegroundColor White
