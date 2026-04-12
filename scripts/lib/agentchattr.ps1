. (Join-Path $PSScriptRoot 'common.ps1')

function Get-AgentchattrRepoPath { Join-Path (Get-HarnessRoot) 'repos/agentchattr' }

function Install-Agentchattr {
    $repo = Get-AgentchattrRepoPath
    if (-not (Test-Path $repo)) { throw 'agentchattr repo missing' }
    Push-Location $repo
    try {
        if (-not (Test-Path '.venv')) {
            & python -m venv .venv
            if ($LASTEXITCODE -ne 0) { throw 'failed to create agentchattr venv' }
        }
        & .\.venv\Scripts\python.exe -m pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) { throw 'failed to install agentchattr requirements' }
    }
    finally { Pop-Location }
}

function Start-Agentchattr {
    $config = Get-StackConfig
    $winDir = Join-Path (Get-AgentchattrRepoPath) 'windows'
    $script = Join-Path $winDir 'start.bat'
    if (-not (Test-Path $script)) { throw "agentchattr launcher not found: $script" }

    Start-BackgroundProcess -Name 'agentchattr' -FilePath 'cmd.exe' -Arguments "/c `"$script`"" -WorkingDirectory $winDir | Out-Null

    if (-not (Wait-HttpOk $config.urls.agentchattrUi 45 1000)) {
        throw "agentchattr UI did not become reachable at $($config.urls.agentchattrUi)"
    }

    if (-not (Wait-TcpPort '127.0.0.1' $config.ports.agentchattrMcpHttp 20 500)) {
        throw "agentchattr MCP HTTP port did not become reachable on $($config.ports.agentchattrMcpHttp)"
    }

    Write-Good "agentchattr UI reachable at $($config.urls.agentchattrUi)"
    Write-Good "agentchattr MCP reachable at $($config.urls.agentchattrMcpHttp)"
}

function Stop-Agentchattr {
    Stop-ManagedProcess 'agentchattr'
}
