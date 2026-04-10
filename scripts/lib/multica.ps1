. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'env.ps1')

function Get-MulticaRepoPath { Join-Path (Get-HarnessRoot) 'repos/multica' }

function Install-MulticaDependencies {
    $repo = Get-MulticaRepoPath
    if (-not (Test-Path $repo)) { throw 'Multica repo missing' }
    Push-Location $repo
    try {
        if (-not (Test-CommandExists 'pnpm')) { throw 'pnpm not found' }
        & pnpm install
        if ($LASTEXITCODE -ne 0) { throw 'pnpm install failed in multica repo' }
    }
    finally { Pop-Location }
}

function Build-Multica {
    $repo = Get-MulticaRepoPath
    Push-Location $repo
    try {
        if (Test-CommandExists 'make') {
            & make build
            if ($LASTEXITCODE -ne 0) { throw 'make build failed' }
        } else {
            Write-Warn 'make not found. Build may need to be run manually according to Multica docs.'
        }
    }
    finally { Pop-Location }
}

function Start-MulticaBackend {
    $repo = Get-MulticaRepoPath
    $serverExe = Join-Path $repo 'server/bin/server.exe'
    if (-not (Test-Path $serverExe)) {
        throw "Multica backend binary not found: $serverExe"
    }
    $envMap = @{
        DATABASE_URL = 'postgres://multica:multica@localhost:5432/multica?sslmode=disable'
        PORT = '8080'
    }
    Start-BackgroundProcess -Name 'multica-backend' -FilePath $serverExe -WorkingDirectory $repo -Environment $envMap | Out-Null
}

function Start-MulticaFrontend {
    $webPath = Join-Path (Get-MulticaRepoPath) 'apps/web'
    if (-not (Test-Path $webPath)) { throw "Multica frontend path missing: $webPath" }
    $envMap = @{
        REMOTE_API_URL = 'http://localhost:8080'
        NEXT_PUBLIC_API_URL = 'http://localhost:8080'
        NEXT_PUBLIC_WS_URL = 'ws://localhost:8080/ws'
    }
    Start-BackgroundProcess -Name 'multica-frontend' -FilePath 'pnpm.cmd' -Arguments 'start' -WorkingDirectory $webPath -Environment $envMap | Out-Null
}

function Stop-MulticaProcesses {
    Stop-ManagedProcess 'multica-backend'
    Stop-ManagedProcess 'multica-frontend'
}
