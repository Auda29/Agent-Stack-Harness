param(
    [switch]$IncludeMultica
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/env.ps1')

$config = Get-StackConfig

Write-Section 'CLI tools (Pi-first core)'
foreach ($cmd in @('git','python','node','docker','pi')) {
    $resolved = Resolve-ExecutablePath $cmd
    if ($resolved) {
        if (Test-CommandExists $cmd) {
            Write-Good "$cmd found"
        } else {
            Write-Warn "$cmd is not visible to Get-Command, but a fallback path was found: $resolved"
        }
    } else {
        $hint = Get-CommandPathHint $cmd
        if ($hint) {
            Write-Warn "$cmd missing in current PowerShell command resolution, but where.exe found: $hint"
        } else {
            Write-Warn "$cmd missing"
        }
    }
}

if ($IncludeMultica) {
    Write-Section 'CLI tools (Multica optional)'
    foreach ($cmd in @('pnpm','go')) {
        $resolved = Resolve-ExecutablePath $cmd
        if ($resolved) {
            if (Test-CommandExists $cmd) {
                Write-Good "$cmd found"
            } else {
                Write-Warn "$cmd is not visible to Get-Command, but a fallback path was found: $resolved"
            }
        } else {
            $hint = Get-CommandPathHint $cmd
            if ($hint) {
                Write-Warn "$cmd missing in current PowerShell command resolution, but where.exe found: $hint"
            } else {
                Write-Warn "$cmd missing"
            }
        }
    }
} else {
    Write-Info 'Multica-only CLI checks skipped (use -IncludeMultica to enable pnpm/go checks)'
}

Write-Section 'Ports (Pi-first core)'
$portsToCheck = @(
    @{ Name='Postgres'; Port=$config.ports.postgres },
    @{ Name='SearXNG'; Port=$config.ports.searxng }
)
if ($IncludeMultica) {
    $portsToCheck += @(
        @{ Name='Multica backend'; Port=$config.ports.multicaBackend },
        @{ Name='Multica frontend'; Port=$config.ports.multicaFrontend }
    )
}
foreach ($pair in $portsToCheck) {
    if (Test-TcpPort '127.0.0.1' $pair.Port) { Write-Good "$($pair.Name) listening on $($pair.Port)" } else { Write-Warn "$($pair.Name) not listening on $($pair.Port)" }
}

Write-Section 'HTTP health (Pi-first core)'
$urlsToCheck = @($config.urls.searxng)
if ($IncludeMultica) {
    $urlsToCheck += @($config.urls.multicaBackendHealth, $config.urls.multicaFrontend)
}
foreach ($u in $urlsToCheck) {
    if (Test-HttpOk $u) { Write-Good "$u reachable" } else { Write-Warn "$u not reachable" }
}

Write-Section 'Config state (Pi-first core)'
if ($IncludeMultica) {
    $multicaEnv = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
    if (Test-Path $multicaEnv) { Write-Good 'Multica .env exists' } else { Write-Warn 'Multica .env missing' }
    if (Test-MulticaEnvComplete) { Write-Good 'Multica Resend settings appear filled' } else { Write-Warn 'Multica Resend settings incomplete' }
} else {
    Write-Info 'Skipping Multica config checks (use -IncludeMultica to enable)'
}

$piSearxngConfig = Join-Path (Get-PiRoot) 'searxng.json'
if (Test-Path $piSearxngConfig) { Write-Good 'pi-searxng config exists' } else { Write-Warn 'pi-searxng config missing' }

if ($config.projectPath) {
    $projectPiDir = Join-Path $config.projectPath '.pi'
    $projectSettings = Join-Path $projectPiDir 'settings.json'
    $projectMcp = Join-Path $projectPiDir 'mcp.json'
    $projectAgents = Join-Path $config.projectPath 'AGENTS.md'

    if (Test-Path $projectSettings) { Write-Good 'Project .pi/settings.json exists' } else { Write-Warn 'Project .pi/settings.json missing' }
    if (Test-Path $projectMcp) { Write-Good 'Project .pi/mcp.json exists' } else { Write-Warn 'Project .pi/mcp.json missing' }
    if (Test-Path $projectAgents) { Write-Good 'Project AGENTS.md exists' } else { Write-Warn 'Project AGENTS.md missing' }
}

Write-Section 'Docker image pulls (core infra)'
foreach ($image in @('searxng/searxng:latest','pgvector/pgvector:pg17')) {
    if (Test-DockerImagePull $image) { Write-Good "$image pull ok" } else { Write-Warn "$image pull failed (check docker login / registry access)" }
}

Write-Section 'Docker containers (core infra)'
foreach ($c in @('postgres','searxng')) {
    if (Test-DockerServiceRunning $c) { Write-Good "$c running" } else { Write-Warn "$c not running" }
}
