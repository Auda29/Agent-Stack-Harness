. (Join-Path $PSScriptRoot 'common.ps1')

function Get-MemPalaceRepoPath { Join-Path (Get-HarnessRoot) 'repos/mempalace' }

function Get-MemPalacePythonPath {
    Join-Path (Get-MemPalaceRepoPath) '.venv/Scripts/python.exe'
}

function Resolve-MemPalacePythonLauncher {
    $candidates = @(
        @('py', '-3.11'),
        @('python3.11'),
        @('python')
    )

    foreach ($candidate in $candidates) {
        $cmd = $candidate[0]
        if (-not (Resolve-ExecutablePath $cmd)) { continue }
        try {
            $versionOutput = if ($candidate.Count -gt 1) {
                & $cmd $candidate[1] --version 2>&1
            } else {
                & $cmd --version 2>&1
            }
            if ($LASTEXITCODE -ne 0) { continue }
            $versionText = ($versionOutput | Out-String)
            if ($versionText -match 'Python\s+3\.11(\.|\s|$)') {
                return ,$candidate
            }
        }
        catch {
            continue
        }
    }

    throw 'Python 3.11 is required for MemPalace on Windows. Install Python 3.11 (for example via winget) and retry.'
}

function Install-MemPalace {
    $repo = Get-MemPalaceRepoPath
    if (-not (Test-Path $repo)) { throw 'MemPalace repo missing' }
    Push-Location $repo
    try {
        if (-not (Test-Path '.venv')) {
            $pythonLauncher = Resolve-MemPalacePythonLauncher
            Write-Info "Creating MemPalace venv with $($pythonLauncher -join ' ')"
            if ($pythonLauncher.Count -gt 1) {
                & $pythonLauncher[0] $pythonLauncher[1] -m venv .venv
            } else {
                & $pythonLauncher[0] -m venv .venv
            }
            if ($LASTEXITCODE -ne 0) { throw 'failed to create MemPalace venv' }
        }
        & .\.venv\Scripts\python.exe -m pip install -e .
        if ($LASTEXITCODE -ne 0) {
            throw 'failed to install MemPalace in editable mode. On Windows this usually means Python 3.11 is missing or Visual C++ Build Tools are required for chroma-hnswlib.'
        }
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
