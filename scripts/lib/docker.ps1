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

function Start-Infrastructure {
    if (-not (Test-DockerAvailable)) { throw 'docker not found in PATH' }
    Sync-DockerComposeEnv
    Push-Location (Get-HarnessRoot)
    try {
        & docker @((Get-DockerComposeArgs) + @('up', '-d'))
        if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }
    }
    finally { Pop-Location }
}

function Stop-Infrastructure {
    if (-not (Test-DockerAvailable)) { throw 'docker not found in PATH' }
    Sync-DockerComposeEnv
    Push-Location (Get-HarnessRoot)
    try {
        & docker @((Get-DockerComposeArgs) + @('down'))
        if ($LASTEXITCODE -ne 0) { throw 'docker compose down failed' }
    }
    finally { Pop-Location }
}

function Test-DockerServiceRunning([string]$ContainerName) {
    try {
        $id = docker ps --filter "name=$ContainerName" --format '{{.Names}}'
        return ($id -match [regex]::Escape($ContainerName))
    }
    catch {
        return $false
    }
}
