Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HarnessRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-ConfigPath {
    Join-Path (Get-HarnessRoot) 'config/stack.json'
}

function Get-StackConfig {
    $path = Get-ConfigPath
    if (-not (Test-Path $path)) { throw "Config not found: $path" }
    Get-Content $path -Raw | ConvertFrom-Json
}

function Save-StackConfig([object]$Config) {
    $path = Get-ConfigPath
    $Config | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
}

function Get-ProjectAgentsTemplatePath {
    Join-Path (Get-HarnessRoot) 'config/AGENTS.md.template'
}

function Get-PiRoot {
    Join-Path $HOME '.pi'
}

function Get-PiAgentRoot {
    Join-Path (Get-PiRoot) 'agent'
}

function Merge-PackageSettings([object[]]$Existing, [string[]]$DefaultSources) {
    $items = @()
    $knownSources = @()

    if ($Existing) {
        foreach ($item in $Existing) {
            $items += $item
            if ($item -is [string]) {
                $knownSources += $item
            }
            elseif ($item.PSObject.Properties.Name -contains 'source') {
                $knownSources += [string]$item.source
            }
        }
    }

    foreach ($source in $DefaultSources) {
        if ($source -and ($knownSources -notcontains $source)) {
            $items += $source
            $knownSources += $source
        }
    }

    return $items
}

function Initialize-PiSearxngConfig {
    $config = Get-StackConfig
    $piRoot = Get-PiRoot
    Ensure-Dir $piRoot

    $path = Join-Path $piRoot 'searxng.json'
    $payload = [ordered]@{
        searxngUrl = $config.urls.searxng
        timeoutMs = 30000
        maxResults = 10
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
    Write-Good "Wrote pi-searxng config: $path"
}

function Initialize-ProjectPiSettings([string]$ProjectPath) {
    if (-not $ProjectPath) { throw 'ProjectPath is required' }

    $resolvedProjectPath = (Resolve-Path $ProjectPath).Path
    $piDir = Join-Path $resolvedProjectPath '.pi'
    Ensure-Dir $piDir

    $path = Join-Path $piDir 'settings.json'
    $settings = if (Test-Path $path) {
        Get-Content $path -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }

    $defaultPackages = @(
        'npm:pi-subagents',
        'npm:pi-searxng',
        'npm:pi-mcp-adapter',
        'npm:pi-lens'
    )

    $settings | Add-Member -NotePropertyName packages -NotePropertyValue @() -Force
    $settings.packages = @(Merge-PackageSettings $settings.packages $defaultPackages)
    $settings | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
    Write-Good "Wrote project pi settings: $path"
}

function Initialize-ProjectMcpConfig([string]$ProjectPath) {
    if (-not $ProjectPath) { throw 'ProjectPath is required' }

    $resolvedProjectPath = (Resolve-Path $ProjectPath).Path
    $piDir = Join-Path $resolvedProjectPath '.pi'
    Ensure-Dir $piDir

    $path = Join-Path $piDir 'mcp.json'
    $mcpConfig = if (Test-Path $path) {
        Get-Content $path -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }

    if ($mcpConfig.PSObject.Properties.Match('mcpServers').Count -eq 0) {
        $mcpConfig | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
    }

    $pythonExe = Join-Path (Get-HarnessRoot) 'repos/mempalace/.venv/Scripts/python.exe'
    $serverConfig = [pscustomobject]@{
        command = $pythonExe
        args = @('-m', 'mempalace.mcp_server')
        lifecycle = 'lazy'
        idleTimeout = 10
    }

    $mcpConfig.mcpServers | Add-Member -NotePropertyName mempalace -NotePropertyValue $serverConfig -Force
    $mcpConfig | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
    Write-Good "Wrote project MCP config: $path"
}

function Initialize-ProjectAgentsMd([string]$ProjectPath, [switch]$Force) {
    if (-not $ProjectPath) { throw 'ProjectPath is required' }

    $config = Get-StackConfig
    $templatePath = Get-ProjectAgentsTemplatePath
    if (-not (Test-Path $templatePath)) { throw "AGENTS template not found: $templatePath" }

    $resolvedProjectPath = (Resolve-Path $ProjectPath).Path
    $target = Join-Path $resolvedProjectPath 'AGENTS.md'
    if ((Test-Path $target) -and -not $Force) {
        Write-Info "AGENTS.md already exists: $target"
        return
    }

    $template = Get-Content $templatePath -Raw
    $content = $template.Replace('__PROJECT_PATH__', $resolvedProjectPath)
    $content = $content.Replace('__HARNESS_ROOT__', (Get-HarnessRoot))
    $content = $content.Replace('__SEARXNG_URL__', $config.urls.searxng)
    $content = $content.Replace('__MULTICA_FRONTEND_URL__', $config.urls.multicaFrontend)
    $content = $content.Replace('__MULTICA_BACKEND_HEALTH_URL__', $config.urls.multicaBackendHealth)
    $content = $content.Replace('__MULTICA_WS_URL__', $config.urls.multicaWebSocket)

    Set-Content -Path $target -Value $content -Encoding UTF8
    Write-Good "Wrote AGENTS.md: $target"
}

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

function Write-Bad([string]$Text) {
    Write-Host "[ERR]  $Text" -ForegroundColor Red
}

function Test-CommandExists([string]$Name) {
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CommandPathHint([string]$Name) {
    try {
        $paths = & where.exe $Name 2>$null
        $joined = (($paths | ForEach-Object { [string]$_ }) -join '; ').Trim()
        if ([string]::IsNullOrWhiteSpace($joined)) { return $null }
        return $joined
    }
    catch {
        return $null
    }
}

function Resolve-ExecutablePath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $hint = Get-CommandPathHint $Name
    if ($hint) {
        $first = ($hint -split ';')[0].Trim()
        if ($first) { return $first }
    }

    $candidates = @()
    switch ($Name.ToLowerInvariant()) {
        'go' {
            if ($env:GOROOT) {
                $candidates += (Join-Path $env:GOROOT 'bin/go.exe')
            }
            $candidates += @(
                'C:\Program Files\Go\bin\go.exe',
                'C:\Program Files (x86)\Go\bin\go.exe'
            )
        }
        'make' {
            $candidates += @(
                'C:\Program Files\Git\usr\bin\make.exe',
                'C:\msys64\usr\bin\make.exe'
            )
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Invoke-Step([string]$Name, [scriptblock]$Script) {
    Write-Section $Name
    try {
        & $Script
        Write-Good "$Name finished"
    }
    catch {
        Write-Bad "$Name failed: $($_.Exception.Message)"
        throw
    }
}

function Test-TcpPort([string]$Address, [int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Address, $Port, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne(1500, $false)
        if (-not $wait) { $client.Close(); return $false }
        $client.EndConnect($async)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Test-HttpOk([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
    }
    catch {
        return $false
    }
}

function Get-ManagedProcessIdPath([string]$Name) {
    Join-Path (Get-HarnessRoot) "data/pids/$Name.pid"
}

function Start-BackgroundProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [hashtable]$Environment = @{}
    )

    $logDir = Join-Path (Get-HarnessRoot) 'data/logs'
    $pidDir = Join-Path (Get-HarnessRoot) 'data/pids'
    $runDir = Join-Path (Get-HarnessRoot) 'data/run'
    Ensure-Dir $logDir
    Ensure-Dir $pidDir
    Ensure-Dir $runDir

    $stdoutFile = Join-Path $logDir "$Name.out.log"
    $stderrFile = Join-Path $logDir "$Name.err.log"
    $pidFile = Get-ManagedProcessIdPath $Name
    $wrapperFile = Join-Path $runDir "$Name.ps1"
    $logSuffix = (Get-Date).ToString('yyyyMMdd-HHmmss')

    $escapedWorkingDirectory = $WorkingDirectory.Replace("'", "''")
    $escapedFilePath = $FilePath.Replace("'", "''")
    $envLines = foreach ($k in $Environment.Keys) {
        $escapedKey = [string]$k
        $escapedValue = ([string]$Environment[$k]).Replace("'", "''")
        "`$env:$escapedKey = '$escapedValue'"
    }

    $invokeLines = if ($Arguments.Count -eq 0) {
        @("& '$escapedFilePath'")
    } else {
        $escapedArgs = $Arguments | ForEach-Object {
            "'" + ([string]$_).Replace("'", "''") + "'"
        }
        $argumentListLiteral = '@(' + ($escapedArgs -join ', ') + ')'
        @(
            "`$argumentList = $argumentListLiteral"
            "& '$escapedFilePath' @argumentList"
        )
    }

    $wrapperContent = @(
        "`$ErrorActionPreference = 'Stop'"
        "Set-Location '$escapedWorkingDirectory'"
        $envLines
        $invokeLines
        'exit $LASTEXITCODE'
    ) -join "`r`n"

    Set-Content -Path $wrapperFile -Value $wrapperContent -Encoding UTF8

    if (Test-Path $stdoutFile) {
        try {
            Remove-Item $stdoutFile -Force -ErrorAction Stop
        }
        catch {
            $stdoutFile = Join-Path $logDir "$Name.$logSuffix.out.log"
            Write-Warn "Could not rotate locked stdout log for $Name; using $stdoutFile"
        }
    }

    if (Test-Path $stderrFile) {
        try {
            Remove-Item $stderrFile -Force -ErrorAction Stop
        }
        catch {
            $stderrFile = Join-Path $logDir "$Name.$logSuffix.err.log"
            Write-Warn "Could not rotate locked stderr log for $Name; using $stderrFile"
        }
    }

    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperFile) `
        -WorkingDirectory $WorkingDirectory `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -WindowStyle Hidden `
        -PassThru

    Start-Sleep -Milliseconds 200
    $startedProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    $metadata = [pscustomobject]@{
        Pid = $proc.Id
        Name = $Name
        FilePath = $FilePath
        WorkingDirectory = $WorkingDirectory
        StdoutPath = $stdoutFile
        StderrPath = $stderrFile
        StartTimeUtc = if ($startedProc) { $startedProc.StartTime.ToUniversalTime().ToString('o') } else { $null }
    }

    $metadata | ConvertTo-Json -Depth 4 | Set-Content -Path $pidFile -Encoding UTF8
    return $proc
}

function Stop-ManagedProcess([string]$Name) {
    $pidFile = Get-ManagedProcessIdPath $Name
    if (-not (Test-Path $pidFile)) {
        Write-Info "$Name is not tracked"
        return
    }

    $raw = Get-Content $pidFile -Raw
    $metadata = $null
    $managedPid = $null

    try {
        $metadata = $raw | ConvertFrom-Json -ErrorAction Stop
        $managedPid = [int]$metadata.Pid
    }
    catch {
        $managedPid = [int]($raw.Trim())
    }

    if ($managedPid) {
        try {
            $proc = Get-Process -Id $managedPid -ErrorAction Stop

            if ($metadata -and $metadata.StartTimeUtc) {
                $expected = [datetime]::Parse($metadata.StartTimeUtc).ToUniversalTime()
                $actual = $proc.StartTime.ToUniversalTime()
                if ($actual -ne $expected) {
                    Write-Warn "$Name PID $managedPid belongs to a different process instance now; refusing to stop it"
                    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
                    return
                }
            }

            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Good "Stopped $Name (PID $($proc.Id))"
        }
        catch {
            Write-Warn "$Name was not running"
        }
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
