param(
    [switch]$IncludeMultica
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/agentchattr.ps1')

$config = Get-StackConfig

Invoke-Step 'Start infrastructure containers' {
    Start-Infrastructure
}

if ($IncludeMultica) {
    Invoke-Step 'Start Multica backend' {
        Start-MulticaBackend
    }

    Invoke-Step 'Start Multica frontend' {
        Start-MulticaFrontend
    }
} else {
    Write-Info 'Skipping Multica backend/frontend startup (use -IncludeMultica to enable)'
}

Invoke-Step 'Start agentchattr' {
    Start-Agentchattr
}

Invoke-Step 'Start pi-agentchattr worker' {
    Start-PiAgentchattrWorker
}

if ($IncludeMultica) {
    Invoke-Step 'Start Multica daemon' {
        Start-MulticaDaemon
    }
}

Write-Section 'Open URLs'
Start-Process $config.urls.agentchattrUi
Write-Good 'Opened agentchattr UI in browser'
if ($IncludeMultica) {
    Start-Process $config.urls.multicaFrontend
    Write-Good 'Opened Multica frontend in browser'
} else {
    Write-Info 'Skipping Multica frontend auto-open (use -IncludeMultica to enable)'
}
Write-Info "SearXNG is running at $($config.urls.searxng) for agent/tool use; it is not opened automatically."

if ($config.projectPath) {
    Write-Info "Saved project path: $($config.projectPath)"
    Write-Info 'Pi worker is using this project path for agentchattr-triggered requests.'
}
