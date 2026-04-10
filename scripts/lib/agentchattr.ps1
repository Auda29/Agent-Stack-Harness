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
    $winDir = Join-Path (Get-AgentchattrRepoPath) 'windows'
    $script = Join-Path $winDir 'start.bat'
    if (-not (Test-Path $script)) { throw "agentchattr launcher not found: $script" }
    Start-BackgroundProcess -Name 'agentchattr' -FilePath 'cmd.exe' -Arguments "/c `"$script`"" -WorkingDirectory $winDir | Out-Null
}

function Stop-Agentchattr {
    Stop-ManagedProcess 'agentchattr'
}
