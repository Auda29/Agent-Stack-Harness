. (Join-Path $PSScriptRoot 'common.ps1')

function Get-AgentchattrRepoPath { Join-Path (Get-HarnessRoot) 'repos/agentchattr' }

function Set-TomlSectionKeyValue([string]$Content, [string]$Section, [string]$Key, [string]$ValueLiteral) {
    $sectionPattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*$.*?(?=^\[|\z)'
    $sectionMatch = [regex]::Match($Content, $sectionPattern)

    if (-not $sectionMatch.Success) {
        $trimmed = $Content.TrimEnd("`r", "`n")
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) { $trimmed += "`r`n`r`n" }
        return $trimmed + "[$Section]`r`n$Key = $ValueLiteral`r`n"
    }

    $sectionText = $sectionMatch.Value
    $keyPattern = '(?m)^' + [regex]::Escape($Key) + '\s*=\s*.*$'
    if ([regex]::IsMatch($sectionText, $keyPattern)) {
        $updatedSection = [regex]::new($keyPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline).Replace($sectionText, "$Key = $ValueLiteral", 1)
    } else {
        $updatedSection = $sectionText.TrimEnd("`r", "`n") + "`r`n$Key = $ValueLiteral`r`n"
    }

    return $Content.Substring(0, $sectionMatch.Index) + $updatedSection + $Content.Substring($sectionMatch.Index + $sectionMatch.Length)
}

function Sync-AgentchattrConfig {
    $config = Get-StackConfig
    $repo = Get-AgentchattrRepoPath
    $path = Join-Path $repo 'config.toml'
    if (-not (Test-Path $path)) { throw "agentchattr config not found: $path" }

    $uiUri = [uri]$config.urls.agentchattrUi
    $httpUri = [uri]$config.urls.agentchattrMcpHttp
    $sseUri = [uri]$config.urls.agentchattrMcpSse

    $content = Get-Content $path -Raw
    $content = Set-TomlSectionKeyValue $content 'server' 'host' ('"' + $uiUri.Host + '"')
    $content = Set-TomlSectionKeyValue $content 'server' 'port' ([string]$uiUri.Port)
    $content = Set-TomlSectionKeyValue $content 'mcp' 'http_port' ([string]$httpUri.Port)
    $content = Set-TomlSectionKeyValue $content 'mcp' 'sse_port' ([string]$sseUri.Port)
    $content = Set-TomlSectionKeyValue $content 'agents.pi' 'command' '"pi"'
    $content = Set-TomlSectionKeyValue $content 'agents.pi' 'cwd' '".."'
    $content = Set-TomlSectionKeyValue $content 'agents.pi' 'color' '"#4f8cff"'
    $content = Set-TomlSectionKeyValue $content 'agents.pi' 'label' '"Pi"'

    Write-TextUtf8NoBom -Path $path -Content $content
    Write-Good "Synced agentchattr config: $path"
}

function Test-AgentchattrHealthy {
    $config = Get-StackConfig
    return (Test-HttpOk $config.urls.agentchattrUi) -and (Test-TcpPort '127.0.0.1' $config.ports.agentchattrMcpHttp)
}

function Stop-AgentchattrPortOwner {
    $config = Get-StackConfig
    try {
        $targetPorts = @($config.ports.agentchattrUi, $config.ports.agentchattrMcpHttp, $config.ports.agentchattrMcpSse)
        $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $targetPorts -contains $_.LocalPort }
        $processIds = @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($procId in $processIds) {
            if ($procId -and $procId -ne 0) {
                try {
                    Stop-Process -Id $procId -Force -ErrorAction Stop
                    Write-Warn "Stopped untracked agentchattr listener process (PID $procId)"
                }
                catch {
                    Write-Warn "Failed to stop untracked agentchattr listener PID $procId"
                }
            }
        }
    }
    catch {
        Write-Warn 'Could not inspect agentchattr listener ownership'
    }
}

function Test-AgentchattrManagedProcessAlive {
    $pidFile = Get-ManagedProcessIdPath 'agentchattr'
    if (-not (Test-Path $pidFile)) { return $false }

    try {
        $metadata = Get-Content $pidFile -Raw | ConvertFrom-Json -ErrorAction Stop
        $proc = Get-Process -Id ([int]$metadata.Pid) -ErrorAction Stop
        if ($metadata.StartTimeUtc) {
            $expected = [datetime]::Parse($metadata.StartTimeUtc).ToUniversalTime()
            $actual = $proc.StartTime.ToUniversalTime()
            if ($actual -ne $expected) { return $false }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Install-Agentchattr {
    $repo = Get-AgentchattrRepoPath
    if (-not (Test-Path $repo)) { throw 'agentchattr repo missing' }
    Push-Location $repo
    try {
        if (-not (Test-Path '.venv')) {
            & python -m venv .venv
            if ($LASTEXITCODE -ne 0) { throw 'failed to create agentchattr venv' }
        }
        & .\.venv\Scripts\python.exe -m pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) { throw 'failed to install agentchattr requirements' }
    }
    finally { Pop-Location }

    Sync-AgentchattrConfig
}

function Start-Agentchattr {
    $config = Get-StackConfig
    $winDir = Join-Path (Get-AgentchattrRepoPath) 'windows'
    $script = Join-Path $winDir 'start.bat'
    if (-not (Test-Path $script)) { throw "agentchattr launcher not found: $script" }

    Sync-AgentchattrConfig

    if (Test-AgentchattrHealthy) {
        if (Test-AgentchattrManagedProcessAlive) {
            Write-Info 'agentchattr already running and healthy; reusing existing managed process'
            return
        }

        Write-Warn 'agentchattr already appears healthy but is not tracked by the harness; restarting it so config changes are applied'
        Stop-AgentchattrPortOwner
        Start-Sleep -Seconds 1
    }

    if (Test-AgentchattrManagedProcessAlive) {
        Write-Warn 'agentchattr is tracked by the harness but unhealthy; restarting it'
        Stop-Agentchattr
    }

    Start-BackgroundProcess -Name 'agentchattr' -FilePath 'cmd.exe' -Arguments "/c `"$script`"" -WorkingDirectory $winDir | Out-Null

    if (-not (Wait-HttpOk $config.urls.agentchattrUi 45 1000)) {
        throw "agentchattr UI did not become reachable at $($config.urls.agentchattrUi)"
    }

    if (-not (Wait-TcpPort '127.0.0.1' $config.ports.agentchattrMcpHttp 20 500)) {
        throw "agentchattr MCP HTTP port did not become reachable on $($config.ports.agentchattrMcpHttp)"
    }

    Write-Good "agentchattr UI reachable at $($config.urls.agentchattrUi)"
    Write-Good "agentchattr MCP reachable at $($config.urls.agentchattrMcpHttp)"
}

function Start-PiAgentchattrWorker {
    $config = Get-StackConfig
    if (-not $config.projectPath) {
        Write-Warn 'Skipping pi-agentchattr worker startup because no projectPath is configured'
        return
    }

    $pythonExe = Resolve-ExecutablePath 'python'
    if (-not $pythonExe) { throw 'python not found for pi-agentchattr worker' }

    $script = Join-Path (Get-HarnessRoot) 'scripts/pi_agentchattr_worker.py'
    if (-not (Test-Path $script)) { throw "pi-agentchattr worker script not found: $script" }

    $healthy = Test-TcpPort '127.0.0.1' $config.ports.agentchattrUi
    if (-not $healthy) { throw 'agentchattr must be running before starting the pi worker' }

    $managedAlive = $false
    $pidFile = Get-ManagedProcessIdPath 'pi-agentchattr-worker'
    if (Test-Path $pidFile) {
        try {
            $metadata = Get-Content $pidFile -Raw | ConvertFrom-Json -ErrorAction Stop
            $proc = Get-Process -Id ([int]$metadata.Pid) -ErrorAction Stop
            $expected = if ($metadata.StartTimeUtc) { [datetime]::Parse($metadata.StartTimeUtc).ToUniversalTime() } else { $null }
            if (-not $expected -or $proc.StartTime.ToUniversalTime() -eq $expected) { $managedAlive = $true }
        }
        catch { $managedAlive = $false }
    }

    if ($managedAlive) {
        Write-Info 'pi-agentchattr worker already running; reusing existing managed process'
        return
    }

    Start-BackgroundProcess -Name 'pi-agentchattr-worker' -FilePath $pythonExe -Arguments @(
        $script,
        '--base-url', $config.urls.agentchattrUi,
        '--project-path', $config.projectPath,
        '--label', 'Pi'
    ) -WorkingDirectory (Get-HarnessRoot) | Out-Null

    Start-Sleep -Seconds 2
    Write-Good 'Started pi-agentchattr worker'
}

function Stop-PiAgentchattrWorker {
    Stop-ManagedProcess 'pi-agentchattr-worker'
}

function Stop-Agentchattr {
    Stop-ManagedProcess 'agentchattr'
    Stop-AgentchattrPortOwner
}
