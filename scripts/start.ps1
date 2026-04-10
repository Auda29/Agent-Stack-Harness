. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/agentchattr.ps1')

$config = Get-StackConfig

Invoke-Step 'Start infrastructure containers' {
    Start-Infrastructure
}

Invoke-Step 'Start Multica backend' {
    Start-MulticaBackend
}

Invoke-Step 'Start Multica frontend' {
    Start-MulticaFrontend
}

Invoke-Step 'Start agentchattr' {
    Start-Agentchattr
}

Invoke-Step 'Start Multica daemon' {
    Start-MulticaDaemon
}

Write-Section 'Open URLs'
Start-Process $config.urls.multicaFrontend
Write-Good 'Opened Multica frontend in browser'
Write-Info "SearXNG is running at $($config.urls.searxng) for agent/tool use; it is not opened automatically."

if ($config.projectPath) {
    Write-Info "Saved project path: $($config.projectPath)"
    Write-Info 'Open a terminal there and start `pi`.'
}
