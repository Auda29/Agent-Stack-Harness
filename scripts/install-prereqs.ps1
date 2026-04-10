param(
    [switch]$IncludeOptionalTools
)

$ErrorActionPreference = 'Stop'

$packages = @(
    @{ Id = 'Git.Git'; Name = 'Git'; Source = 'winget' },
    @{ Id = 'Docker.DockerDesktop'; Name = 'Docker Desktop'; Source = 'winget' },
    @{ Id = 'Python.Python.3.11'; Name = 'Python 3.11'; Source = 'winget' },
    @{ Id = 'OpenJS.NodeJS'; Name = 'Node.js'; Source = 'winget' },
    @{ Id = 'pnpm.pnpm'; Name = 'pnpm'; Source = 'winget' },
    @{ Id = 'GoLang.Go'; Name = 'Go'; Source = 'winget' }
)

$optionalPackages = @(
    @{ Id = 'Anthropic.Claude'; Name = 'Claude'; Source = 'winget' }
)

function Write-Section([string]$Text) {
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Write-Info([string]$Text) {
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

function Write-Good([string]$Text) {
    Write-Host "[OK]   $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Test-CommandExists([string]$Name) {
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage([hashtable]$Package) {
    Write-Info "Installing $($Package.Name) via winget ($($Package.Id))"
    & winget install --id $Package.Id --exact --accept-package-agreements --accept-source-agreements --source $Package.Source
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $($Package.Id)"
    }
}

Write-Section 'Check winget'
if (-not (Test-CommandExists 'winget')) {
    throw 'winget not found. Install App Installer from Microsoft Store or use manual setup.'
}
Write-Good 'winget found'

Write-Section 'Install core prerequisites'
foreach ($package in $packages) {
    Install-WingetPackage $package
}

Write-Section 'Post-install npm globals'
if (-not (Test-CommandExists 'npm')) {
    Write-Warn 'npm not found after Node.js install. Open a new shell and run this script again if needed.'
} else {
    Write-Info 'Installing Codex CLI globally via npm'
    & npm install -g @openai/codex
    if ($LASTEXITCODE -ne 0) {
        throw 'npm install -g @openai/codex failed'
    }
    Write-Good 'Installed Codex CLI'
}

if ($IncludeOptionalTools) {
    Write-Section 'Install optional GUI tools'
    foreach ($package in $optionalPackages) {
        try {
            Install-WingetPackage $package
        }
        catch {
            Write-Warn "Optional install failed for $($package.Name): $($_.Exception.Message)"
        }
    }
}

Write-Section 'Manual follow-up'
Write-Host 'Some tools may require a new terminal session before they appear in PATH.' -ForegroundColor White
Write-Host 'You still need to log into Claude Code and Codex CLI manually.' -ForegroundColor White
Write-Host 'If Claude Code is not available via winget on your machine, install it manually.' -ForegroundColor White
Write-Host 'Next step: run .\scripts\install.ps1' -ForegroundColor White
