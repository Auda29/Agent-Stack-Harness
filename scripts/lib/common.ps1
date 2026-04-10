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

function Test-TcpPort([string]$Host, [int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Host, $Port, $null, $null)
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
    if (Test-Path $stdoutFile) { Remove-Item $stdoutFile -Force }
    if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force }

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
    $pid = $null

    try {
        $metadata = $raw | ConvertFrom-Json -ErrorAction Stop
        $pid = [int]$metadata.Pid
    }
    catch {
        $pid = [int]($raw.Trim())
    }

    if ($pid) {
        try {
            $proc = Get-Process -Id $pid -ErrorAction Stop

            if ($metadata -and $metadata.StartTimeUtc) {
                $expected = [datetime]::Parse($metadata.StartTimeUtc).ToUniversalTime()
                $actual = $proc.StartTime.ToUniversalTime()
                if ($actual -ne $expected) {
                    Write-Warn "$Name PID $pid belongs to a different process instance now; refusing to stop it"
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
