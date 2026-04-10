. (Join-Path $PSScriptRoot 'common.ps1')

function Test-DockerAvailable {
    Test-CommandExists 'docker'
}

function Get-DockerComposeEnvPath {
    Join-Path (Get-HarnessRoot) '.env'
}

function Sync-DockerComposeEnv {
    $config = Get-StackConfig
    $envPath = Get-DockerComposeEnvPath
    $content = @(
        "POSTGRES_PORT=$($config.ports.postgres)"
        "SEARXNG_PORT=$($config.ports.searxng)"
    ) -join "`r`n"
    Set-Content -Path $envPath -Value ($content + "`r`n") -Encoding UTF8
}

function Get-DockerComposeArgs {
    $root = Get-HarnessRoot
    $config = Get-StackConfig
    return @('compose', '-p', $config.dockerProjectName, '-f', (Join-Path $root 'docker-compose.yml'))
}

function Invoke-DockerCommand([string[]]$Arguments) {
    $previousEap = $ErrorActionPreference
    $nativePreferenceWasPresent = Test-Path Variable:PSNativeCommandUseErrorActionPreference
    if ($nativePreferenceWasPresent) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = 'Continue'
        if ($nativePreferenceWasPresent) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & docker @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = (($output | ForEach-Object { [string]$_ }) -join "`n")
        }
    }
    finally {
        $ErrorActionPreference = $previousEap
        if ($nativePreferenceWasPresent) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }
}

function Get-DockerAuthHelpMessage {
    @(
        'Docker image pull failed due to an authentication problem.'
        'Try:'
        '  docker logout'
        '  docker login'
        '  docker pull searxng/searxng:latest'
        '  docker pull pgvector/pgvector:pg17'
        'Then rerun scripts/install.ps1'
    ) -join "`n"
}

function Assert-DockerCommandSucceeded([object]$Result, [string]$Context) {
    if ($Result.ExitCode -eq 0) { return }

    $output = $Result.Output
    if ($output) { Write-Host $output }

    if ($output -match 'authentication required' -or
        $output -match 'incorrect username or password' -or
        $output -match 'unauthorized' -or
        $output -match 'denied: requested access to the resource is denied') {
        throw "$Context`n`n$(Get-DockerAuthHelpMessage)"
    }

    throw $Context
}

function Test-DockerImagePull([string]$Image) {
    if (-not (Test-DockerAvailable)) { return $false }
    try {
        $result = Invoke-DockerCommand @('pull', $Image)
        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Start-Infrastructure {
    if (-not (Test-DockerAvailable)) { throw 'docker not found in PATH' }
    Sync-DockerComposeEnv
    Push-Location (Get-HarnessRoot)
    try {
        $result = Invoke-DockerCommand ((Get-DockerComposeArgs) + @('up', '-d'))
        Assert-DockerCommandSucceeded $result 'docker compose up failed'
    }
    finally { Pop-Location }

    $config = Get-StackConfig
    if (-not (Wait-TcpPort '127.0.0.1' $config.ports.postgres 30 500)) {
        throw "Postgres did not become ready on port $($config.ports.postgres) after docker compose up"
    }
    if (-not (Wait-TcpPort '127.0.0.1' $config.ports.searxng 30 500)) {
        throw "SearXNG did not become ready on port $($config.ports.searxng) after docker compose up"
    }
}

function Stop-Infrastructure {
    if (-not (Test-DockerAvailable)) { throw 'docker not found in PATH' }
    Sync-DockerComposeEnv
    Push-Location (Get-HarnessRoot)
    try {
        $result = Invoke-DockerCommand ((Get-DockerComposeArgs) + @('down'))
        Assert-DockerCommandSucceeded $result 'docker compose down failed'
    }
    finally { Pop-Location }
}

function Test-DockerServiceRunning([string]$ServiceName) {
    try {
        $config = Get-StackConfig
        $project = $config.dockerProjectName
        $names = docker ps `
            --filter "label=com.docker.compose.project=$project" `
            --filter "label=com.docker.compose.service=$ServiceName" `
            --format '{{.Names}}'
        return (-not [string]::IsNullOrWhiteSpace(($names | Out-String).Trim()))
    }
    catch {
        return $false
    }
}
