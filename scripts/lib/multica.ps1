. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'env.ps1')

function Get-MulticaRepoPath { Join-Path (Get-HarnessRoot) 'repos/multica' }

function Get-MulticaBackendBinaryPath {
    Join-Path (Get-MulticaRepoPath) 'server/bin/server.exe'
}

function Get-MulticaServerPath {
    Join-Path (Get-MulticaRepoPath) 'server'
}

function Get-MulticaRuntimeSettings {
    $config = Get-StackConfig
    return [pscustomobject]@{
        DatabaseUrl = "postgres://multica:multica@localhost:$($config.ports.postgres)/multica?sslmode=disable"
        BackendPort = [string]$config.ports.multicaBackend
        FrontendUrl = $config.urls.multicaFrontend
        BackendUrl = "http://localhost:$($config.ports.multicaBackend)"
        WebSocketUrl = "ws://localhost:$($config.ports.multicaBackend)/ws"
    }
}

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
    $serverExe = Get-MulticaBackendBinaryPath

    if (Test-Path $serverExe) {
        Write-Info "Multica backend binary already exists: $serverExe"
        return
    }

    Push-Location $repo
    try {
        $makeExe = Resolve-ExecutablePath 'make'
        $goExe = Resolve-ExecutablePath 'go'
        $serverPath = Get-MulticaServerPath

        if ($makeExe) {
            & $makeExe build
            if ($LASTEXITCODE -ne 0) { throw 'make build failed' }
        }
        elseif ($goExe) {
            if (-not (Test-Path (Join-Path $serverPath 'go.mod'))) {
                throw "Multica Go module not found: $(Join-Path $serverPath 'go.mod')"
            }

            Write-Warn "make not found; attempting Go build fallback for Multica backend using $goExe"
            Ensure-Dir (Join-Path $repo 'server/bin')

            Push-Location $serverPath
            try {
                & $goExe build -o $serverExe ./cmd/server
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path $serverExe)) {
                    throw 'automatic Go build fallback failed'
                }
            }
            finally { Pop-Location }
        }
        else {
            throw 'neither make nor go is available to build Multica'
        }
    }
    finally { Pop-Location }

    if (-not (Test-Path $serverExe)) {
        throw "Multica backend binary still missing after build attempt: $serverExe"
    }
}

function Start-MulticaBackend {
    $repo = Get-MulticaRepoPath
    $serverExe = Get-MulticaBackendBinaryPath
    if (-not (Test-Path $serverExe)) {
        Write-Warn 'Multica backend binary missing; attempting build now'
        Build-Multica
    }
    if (-not (Test-Path $serverExe)) {
        throw "Multica backend binary not found: $serverExe"
    }

    $runtime = Get-MulticaRuntimeSettings
    $envMap = @{
        DATABASE_URL = $runtime.DatabaseUrl
        PORT = $runtime.BackendPort
    }
    Start-BackgroundProcess -Name 'multica-backend' -FilePath $serverExe -WorkingDirectory $repo -Environment $envMap | Out-Null
}

function Start-MulticaFrontend {
    $webPath = Join-Path (Get-MulticaRepoPath) 'apps/web'
    if (-not (Test-Path $webPath)) { throw "Multica frontend path missing: $webPath" }

    $runtime = Get-MulticaRuntimeSettings
    $envMap = @{
        REMOTE_API_URL = $runtime.BackendUrl
        NEXT_PUBLIC_API_URL = $runtime.BackendUrl
        NEXT_PUBLIC_WS_URL = $runtime.WebSocketUrl
    }
    Start-BackgroundProcess -Name 'multica-frontend' -FilePath 'pnpm.cmd' -Arguments @('start') -WorkingDirectory $webPath -Environment $envMap | Out-Null
}

function Stop-MulticaProcesses {
    Stop-ManagedProcess 'multica-backend'
    Stop-ManagedProcess 'multica-frontend'
}
