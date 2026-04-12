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

    Write-TextUtf8NoBom -Path $path -Content $content
    Write-Good "Synced agentchattr config: $path"
}

function Test-AgentchattrHealthy {
    $config = Get-StackConfig
    return (Test-HttpOk $config.urls.agentchattrUi) -and (Test-TcpPort '127.0.0.1' $config.ports.agentchattrMcpHttp)
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
        } else {
            Write-Warn 'agentchattr already appears healthy but is not tracked by the harness; reusing existing instance'
        }
        return
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

function Stop-Agentchattr {
    Stop-ManagedProcess 'agentchattr'
}
