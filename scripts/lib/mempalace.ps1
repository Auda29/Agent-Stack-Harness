. (Join-Path $PSScriptRoot 'common.ps1')

function Get-MemPalaceRepoPath { Join-Path (Get-HarnessRoot) 'repos/mempalace' }

function Install-MemPalace {
    $repo = Get-MemPalaceRepoPath
    if (-not (Test-Path $repo)) { throw 'MemPalace repo missing' }
    Push-Location $repo
    try {
        if (-not (Test-Path '.venv')) {
            & python -m venv .venv
            if ($LASTEXITCODE -ne 0) { throw 'failed to create MemPalace venv' }
        }
        & .\.venv\Scripts\python.exe -m pip install -e .
        if ($LASTEXITCODE -ne 0) { throw 'failed to install MemPalace in editable mode' }
    }
    finally { Pop-Location }
}
