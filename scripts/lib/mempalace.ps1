. (Join-Path $PSScriptRoot 'common.ps1')

function Get-MemPalaceRepoPath { Join-Path (Get-HarnessRoot) 'repos/mempalace' }

function Get-MemPalacePythonPath {
    Join-Path (Get-MemPalaceRepoPath) '.venv/Scripts/python.exe'
}

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

function Invoke-MemPalaceCli {
    param(
        [string[]]$Arguments
    )

    $pythonExe = Get-MemPalacePythonPath
    if (-not (Test-Path $pythonExe)) {
        throw "MemPalace Python executable not found: $pythonExe"
    }

    & $pythonExe -m mempalace.cli @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "MemPalace command failed: mempalace $($Arguments -join ' ')"
    }
}

function Initialize-MemPalaceProject([string]$ProjectPath) {
    if (-not $ProjectPath) { throw 'ProjectPath is required' }
    $resolvedProjectPath = (Resolve-Path $ProjectPath).Path
    Invoke-MemPalaceCli -Arguments @('init', $resolvedProjectPath, '--yes')
}

function Test-MemPalaceStatus {
    try {
        Invoke-MemPalaceCli -Arguments @('status')
        return $true
    }
    catch {
        return $false
    }
}
