param(
    [string]$ProjectPath = ''
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/env.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/agentchattr.ps1')
. (Join-Path $PSScriptRoot 'lib/mempalace.ps1')

$root = Get-HarnessRoot
$config = Get-StackConfig

Invoke-Step 'Prepare folders' {
    Ensure-Dir (Join-Path $root 'data')
    Ensure-Dir (Join-Path $root 'repos')
    Ensure-Dir (Join-Path $root 'data/logs')
}

Invoke-Step 'Check prerequisites' {
    foreach ($cmd in @('git','python','node','docker')) {
        if (Test-CommandExists $cmd) { Write-Good "$cmd found" } else { Write-Warn "$cmd not found" }
    }
    if (-not (Test-CommandExists 'pnpm')) { Write-Warn 'pnpm not found; Multica frontend install will fail until installed' }
    if (-not (Test-CommandExists 'go')) { Write-Warn 'go not found; Multica backend build may fail until installed' }
}

Invoke-Step 'Clone or update repositories' {
    foreach ($name in $config.repos.PSObject.Properties.Name) {
        $url = $config.repos.$name
        $target = Join-Path $root "repos/$name"
        if (Test-Path $target) {
            Write-Info "Updating $name"
            Push-Location $target
            try {
                & git pull --ff-only
            } finally { Pop-Location }
        } else {
            Write-Info "Cloning $name"
            & git clone $url $target
        }
    }
}

Invoke-Step 'Write Multica env' {
    Initialize-MulticaEnv
}

Invoke-Step 'Start docker infrastructure' {
    Start-Infrastructure
}

Invoke-Step 'Install agentchattr dependencies' {
    Install-Agentchattr
}

Invoke-Step 'Install MemPalace editable environment' {
    Install-MemPalace
}

Invoke-Step 'Install Multica dependencies' {
    Install-MulticaDependencies
}

Invoke-Step 'Build Multica backend' {
    Build-Multica
}

if ($ProjectPath) {
    Invoke-Step 'Persist project path' {
        if (-not (Test-Path $ProjectPath)) {
            throw "ProjectPath does not exist: $ProjectPath"
        }
        $resolved = (Resolve-Path $ProjectPath).Path
        $config.projectPath = $resolved
        Save-StackConfig $config
        Write-Good "Saved projectPath: $resolved"
    }
}

Write-Host "`nInstall phase completed. Run onboarding.ps1 next." -ForegroundColor Cyan
