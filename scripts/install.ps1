param(
    [string]$ProjectPath = '',
    [switch]$IncludeMultica
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
    if (-not (Resolve-ExecutablePath 'pnpm')) { Write-Warn 'pnpm not found; Multica frontend install will fail until installed' }
    $goPath = Resolve-ExecutablePath 'go'
    if (-not $goPath) {
        Write-Warn 'go not found; Multica backend build may fail until installed'
    } elseif (-not (Test-CommandExists 'go')) {
        Write-Warn "go is not visible to Get-Command, but a fallback path was found: $goPath"
    } else {
        Write-Good "go found ($goPath)"
    }
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

if ($IncludeMultica) {
    Invoke-Step 'Write Multica env' {
        Initialize-MulticaEnv
    }
} else {
    Write-Info 'Skipping Multica env setup (use -IncludeMultica to enable)'
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

if ($IncludeMultica) {
    Invoke-Step 'Install Multica dependencies' {
        Install-MulticaDependencies
    }

    Invoke-Step 'Build Multica backend' {
        Build-Multica
    }

    Invoke-Step 'Run Multica migrations' {
        Invoke-MulticaMigrations
    }
} else {
    Write-Info 'Skipping Multica install/build/migrations (use -IncludeMultica to enable)'
}

Invoke-Step 'Configure pi-searxng' {
    Initialize-PiSearxngConfig
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

    Invoke-Step 'Bootstrap project pi settings' {
        Initialize-ProjectPiSettings -ProjectPath $config.projectPath
    }

    Invoke-Step 'Bootstrap project MCP config' {
        Initialize-ProjectMcpConfig -ProjectPath $config.projectPath
    }

    Invoke-Step 'Bootstrap project AGENTS.md' {
        Initialize-ProjectAgentsMd -ProjectPath $config.projectPath
    }
}

Write-Host "`nInstall phase completed. Run onboarding.ps1 next." -ForegroundColor Cyan
