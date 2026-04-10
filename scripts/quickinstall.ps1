param(
    [string]$ProjectPath = '',
    [switch]$IncludeOptionalTools,
    [switch]$SkipPrereqs,
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'

function Write-Section([string]$Text) {
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

$scriptRoot = $PSScriptRoot

if (-not $SkipPrereqs) {
    Write-Section 'Quick install: prerequisites'
    & (Join-Path $scriptRoot 'install-prereqs.ps1') @(
        if ($IncludeOptionalTools) { '-IncludeOptionalTools' }
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'install-prereqs.ps1 failed'
    }
}

Write-Section 'Quick install: stack install'
$installArgs = @()
if ($ProjectPath) {
    $installArgs += @('-ProjectPath', $ProjectPath)
}
& (Join-Path $scriptRoot 'install.ps1') @installArgs
if ($LASTEXITCODE -ne 0) {
    throw 'install.ps1 failed'
}

Write-Section 'Quick install: onboarding'
& (Join-Path $scriptRoot 'onboarding.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'onboarding.ps1 failed'
}

if (-not $SkipStart) {
    Write-Section 'Quick install: start'
    & (Join-Path $scriptRoot 'start.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'start.ps1 failed'
    }
}

Write-Section 'Quick install complete'
Write-Host 'Next steps:' -ForegroundColor White
Write-Host '  1) Open your target project folder' -ForegroundColor White
Write-Host '  2) Run `pi`' -ForegroundColor White
Write-Host '  3) Run `/login` inside pi' -ForegroundColor White
Write-Host '  4) For daily use later, run .\scripts\start.ps1' -ForegroundColor White
