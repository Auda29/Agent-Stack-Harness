param(
    [switch]$IncludeOptionalTools
)

$ErrorActionPreference = 'Stop'

$packages = @(
    @{ Id = 'Git.Git'; Name = 'Git'; Source = 'winget'; Command = 'git' },
    @{ Id = 'Docker.DockerDesktop'; Name = 'Docker Desktop'; Source = 'winget'; Command = 'docker' },
    @{ Id = 'Python.Python.3.11'; Name = 'Python 3.11'; Source = 'winget'; Command = 'python' },
    @{ Id = 'OpenJS.NodeJS'; Name = 'Node.js'; Source = 'winget'; Command = 'node' },
    @{ Id = 'pnpm.pnpm'; Name = 'pnpm'; Source = 'winget'; Command = 'pnpm' },
    @{ Id = 'GoLang.Go'; Name = 'Go'; Source = 'winget'; Command = 'go' }
)

$piPackages = @(
    @{ Source = 'npm:pi-subagents'; Name = 'pi-subagents' },
    @{ Source = 'npm:pi-searxng'; Name = 'pi-searxng' },
    @{ Source = 'npm:pi-mcp-adapter'; Name = 'pi-mcp-adapter' },
    @{ Source = 'npm:pi-lens'; Name = 'pi-lens' },
    @{ Source = 'npm:@tintinweb/pi-tasks'; Name = 'pi-tasks' }
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

function Test-WingetPackageInstalled([hashtable]$Package) {
    try {
        $output = & winget list --id $Package.Id --exact --accept-source-agreements 2>$null
        return ($LASTEXITCODE -eq 0 -and (($output | Out-String) -match [regex]::Escape($Package.Id)))
    }
    catch {
        return $false
    }
}

function Install-WingetPackage([hashtable]$Package) {
    if ($Package.Command -and (Test-CommandExists $Package.Command)) {
        Write-Good "$($Package.Name) already available in PATH"
        return
    }

    if (Test-WingetPackageInstalled $Package) {
        Write-Info "$($Package.Name) is already installed via winget"
        return
    }

    Write-Info "Installing $($Package.Name) via winget ($($Package.Id))"
    & winget install --id $Package.Id --exact --accept-package-agreements --accept-source-agreements --source $Package.Source
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $($Package.Id)"
    }
}

function Test-PiPackageInstalled([hashtable]$Package) {
    try {
        $output = & pi list 2>$null
        return ($LASTEXITCODE -eq 0 -and (($output | Out-String) -match [regex]::Escape($Package.Source)))
    }
    catch {
        return $false
    }
}

function Install-PiPackage([hashtable]$Package) {
    if (Test-PiPackageInstalled $Package) {
        Write-Good "$($Package.Name) already installed in pi"
        return
    }

    Write-Info "Installing pi package $($Package.Source)"
    & pi install $Package.Source
    if ($LASTEXITCODE -ne 0) {
        throw "pi install failed for $($Package.Source)"
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
} elseif (Test-CommandExists 'pi') {
    Write-Good 'pi-coding-agent already available in PATH'
} else {
    Write-Info 'Installing pi-coding-agent globally via npm'
    & npm install -g @mariozechner/pi-coding-agent
    if ($LASTEXITCODE -ne 0) {
        throw 'npm install -g @mariozechner/pi-coding-agent failed'
    }
    Write-Good 'Installed pi-coding-agent'
}

Write-Section 'Install default pi packages'
if (-not (Test-CommandExists 'pi')) {
    Write-Warn 'pi not found after install. Open a new shell and run this script again if needed.'
} else {
    foreach ($package in $piPackages) {
        Install-PiPackage $package
    }
}

if ($IncludeOptionalTools) {
    Write-Section 'Optional tools'
    Write-Info 'No optional GUI tools are configured right now.'
}

Write-Section 'Manual follow-up'
Write-Host 'Some tools may require a new terminal session before they appear in PATH.' -ForegroundColor White
Write-Host 'You still need to log into pi manually: run `pi`, then `/login` or use provider API keys.' -ForegroundColor White
Write-Host 'Default pi packages are also installed: pi-subagents, pi-searxng, pi-mcp-adapter, pi-lens, pi-tasks.' -ForegroundColor White
Write-Host 'Next step: run .\scripts\install.ps1' -ForegroundColor White
