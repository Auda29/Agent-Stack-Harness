. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'env.ps1')

function Get-MulticaRepoPath { Join-Path (Get-HarnessRoot) 'repos/multica' }

function Get-MulticaBackendBinaryPath {
    Join-Path (Get-MulticaRepoPath) 'server/bin/server.exe'
}

function Get-MulticaMigrateBinaryPath {
    Join-Path (Get-MulticaRepoPath) 'server/bin/migrate.exe'
}

function Get-MulticaCliBinaryPath {
    Join-Path (Get-MulticaRepoPath) 'server/bin/multica.exe'
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

function Ensure-MulticaHarnessPatches {
    $repo = Get-MulticaRepoPath
    if (-not (Test-Path $repo)) { throw 'Multica repo missing' }

    $cmdDir = Join-Path $repo 'server/cmd/multica'
    Ensure-Dir $cmdDir

    $unixPath = Join-Path $cmdDir 'sysproc_unix.go'
    $windowsPath = Join-Path $cmdDir 'sysproc_windows.go'
    $daemonPath = Join-Path $cmdDir 'cmd_daemon.go'
    $authPath = Join-Path $cmdDir 'cmd_auth.go'

    $unixContent = @'
//go:build !windows

package main

import (
    "os/exec"
    "syscall"
)

func setBackgroundSysProcAttr(cmd *exec.Cmd) {
    cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
}
'@

    $windowsContent = @'
//go:build windows

package main

import "os/exec"

func setBackgroundSysProcAttr(cmd *exec.Cmd) {
    // No special SysProcAttr is required here for the Windows background daemon path.
}
'@

    Set-Content -Path $unixPath -Value $unixContent -Encoding UTF8
    Set-Content -Path $windowsPath -Value $windowsContent -Encoding UTF8

    if (Test-Path $daemonPath) {
        $daemonContent = Get-Content $daemonPath -Raw
        $updatedDaemonContent = $daemonContent.Replace("child.SysProcAttr = &syscall.SysProcAttr{Setsid: true}", 'setBackgroundSysProcAttr(child)')
        if ($updatedDaemonContent -ne $daemonContent) {
            Set-Content -Path $daemonPath -Value $updatedDaemonContent -Encoding UTF8
        }
    }

    if (Test-Path $authPath) {
        $authContent = Get-Content $authPath -Raw
        $updatedAuthContent = $authContent.Replace("`tcase \"windows\":`r`n`t`tcmd = \"cmd\"`r`n`t`targs = []string{\"/c\", \"start\", url}", "`tcase \"windows\":`r`n`t`tcmd = \"rundll32\"`r`n`t`targs = []string{\"url.dll,FileProtocolHandler\", url}")
        if ($updatedAuthContent -ne $authContent) {
            Set-Content -Path $authPath -Value $updatedAuthContent -Encoding UTF8
        }
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
    Ensure-MulticaHarnessPatches

    $repo = Get-MulticaRepoPath
    $serverExe = Get-MulticaBackendBinaryPath
    $migrateExe = Get-MulticaMigrateBinaryPath
    $cliExe = Get-MulticaCliBinaryPath

    if ((Test-Path $serverExe) -and (Test-Path $migrateExe) -and (Test-Path $cliExe)) {
        Write-Info "Multica binaries already exist: $serverExe ; $migrateExe ; $cliExe"
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
                if (-not (Test-Path $serverExe)) {
                    & $goExe build -o $serverExe ./cmd/server
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $serverExe)) {
                        throw 'automatic Go build fallback failed for server'
                    }
                }

                if (-not (Test-Path $migrateExe)) {
                    & $goExe build -o $migrateExe ./cmd/migrate
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $migrateExe)) {
                        throw 'automatic Go build fallback failed for migrate'
                    }
                }

                if (-not (Test-Path $cliExe)) {
                    & $goExe build -o $cliExe ./cmd/multica
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $cliExe)) {
                        Write-Warn 'automatic Go build fallback failed for multica cli; Multica daemon integration may be unavailable on this platform'
                    }
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
    if (-not (Test-Path $migrateExe)) {
        throw "Multica migrate binary still missing after build attempt: $migrateExe"
    }
    if (-not (Test-Path $cliExe)) {
        Write-Warn "Multica CLI binary is still missing after build attempt: $cliExe"
    }
}

function Invoke-MulticaMigrations {
    $repo = Get-MulticaRepoPath
    $serverPath = Get-MulticaServerPath
    $migrateExe = Get-MulticaMigrateBinaryPath
    $runtime = Get-MulticaRuntimeSettings
    $config = Get-StackConfig

    if (-not (Test-Path $migrateExe)) {
        Build-Multica
    }

    if (-not (Wait-TcpPort '127.0.0.1' $config.ports.postgres 30 500)) {
        throw "Postgres is not ready on port $($config.ports.postgres); cannot run Multica migrations"
    }

    $env:DATABASE_URL = $runtime.DatabaseUrl
    try {
        if (Test-Path $migrateExe) {
            Push-Location $serverPath
            try {
                & $migrateExe up
                if ($LASTEXITCODE -ne 0) { throw 'Multica migrations failed' }
            }
            finally { Pop-Location }
        }
        else {
            $goExe = Resolve-ExecutablePath 'go'
            if (-not $goExe) {
                throw 'Multica migrate binary missing and go not available for fallback migration run'
            }

            Push-Location $serverPath
            try {
                & $goExe run ./cmd/migrate up
                if ($LASTEXITCODE -ne 0) { throw 'Multica migrations failed' }
            }
            finally { Pop-Location }
        }
    }
    finally {
        Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
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

    Invoke-MulticaMigrations

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
        FRONTEND_PORT = [string](Get-StackConfig).ports.multicaFrontend
        REMOTE_API_URL = $runtime.BackendUrl
        NEXT_PUBLIC_API_URL = $runtime.BackendUrl
        NEXT_PUBLIC_WS_URL = $runtime.WebSocketUrl
    }
    Start-BackgroundProcess -Name 'multica-frontend' -FilePath 'pnpm.cmd' -Arguments @('exec', 'next', 'dev', '--port', $envMap.FRONTEND_PORT) -WorkingDirectory $webPath -Environment $envMap | Out-Null
}

function Test-MulticaCliAuthenticated {
    $configPath = Join-Path $HOME '.multica/config.json'
    if (-not (Test-Path $configPath)) { return $false }

    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
        return (-not [string]::IsNullOrWhiteSpace([string]$cfg.Token))
    }
    catch {
        return $false
    }
}

function Invoke-MulticaCliLogin {
    $cliExe = Get-MulticaCliBinaryPath
    if (-not (Test-Path $cliExe)) {
        Write-Warn 'Multica CLI binary missing; attempting build now'
        try {
            Build-Multica
        }
        catch {
            Write-Warn "Multica CLI build attempt failed while preparing login: $($_.Exception.Message)"
        }
    }
    if (-not (Test-Path $cliExe)) {
        Write-Warn "Multica CLI binary not found: $cliExe"
        return
    }

    if (Test-MulticaCliAuthenticated) {
        Write-Good 'Multica CLI already logged in'
        return
    }

    $runtime = Get-MulticaRuntimeSettings
    $null = & $cliExe config set server-url $runtime.BackendUrl 2>&1
    $null = & $cliExe config set app-url $runtime.FrontendUrl 2>&1

    Write-Info 'Starting interactive Multica CLI login. Complete the login flow in the browser/terminal prompts.'
    & $cliExe login

    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Multica CLI login did not complete successfully'
        return
    }

    if (Test-MulticaCliAuthenticated) {
        Write-Good 'Multica CLI login completed'
    }
    else {
        Write-Warn 'Multica CLI login finished but no token was detected yet'
    }
}

function Start-MulticaDaemon {
    $cliExe = Get-MulticaCliBinaryPath
    if (-not (Test-Path $cliExe)) {
        Write-Warn 'Multica CLI binary missing; attempting build now'
        try {
            Build-Multica
        }
        catch {
            Write-Warn "Multica CLI build attempt failed while preparing daemon start: $($_.Exception.Message)"
        }
    }
    if (-not (Test-Path $cliExe)) {
        Write-Warn "Multica CLI binary not found: $cliExe`nSkipping daemon start. This is likely an upstream Windows CLI/daemon build limitation, not a stack startup failure."
        return
    }

    if (-not (Test-MulticaCliAuthenticated)) {
        Write-Warn 'Multica CLI is not logged in yet. Skipping daemon start. Run `multica login` after logging into the web app, then rerun start.ps1.'
        return
    }

    $runtime = Get-MulticaRuntimeSettings
    $output = & $cliExe config set server-url $runtime.BackendUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not update Multica CLI server-url automatically: $((($output | ForEach-Object { [string]$_ }) -join ' ').Trim())"
    }

    $output = & $cliExe config set app-url $runtime.FrontendUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not update Multica CLI app-url automatically: $((($output | ForEach-Object { [string]$_ }) -join ' ').Trim())"
    }

    $output = & $cliExe daemon start 2>&1
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($text -match 'already running') {
            Write-Info "Multica daemon already running`n$text"
            return
        }
        Write-Warn "Multica daemon did not start cleanly. Run `multica daemon logs` or `multica daemon status` for details.`n$text"
        return
    }

    if ($text) {
        Write-Good $text
    } else {
        Write-Good 'Multica daemon start command completed'
    }
}

function Stop-MulticaDaemon {
    $cliExe = Get-MulticaCliBinaryPath
    if (-not (Test-Path $cliExe)) {
        Write-Info 'Multica CLI binary not present; daemon stop skipped'
        return
    }

    $output = & $cliExe daemon stop 2>&1
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Multica daemon stop reported an issue.`n$text"
        return
    }

    if ($text) {
        Write-Good $text
    } else {
        Write-Good 'Multica daemon stop command completed'
    }
}

function Stop-MulticaProcesses {
    Stop-ManagedProcess 'multica-backend'
    Stop-ManagedProcess 'multica-frontend'
}
