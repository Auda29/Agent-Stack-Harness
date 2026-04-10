. (Join-Path $PSScriptRoot 'common.ps1')

function Set-DotEnvValue([string]$Content, [string]$Key, [string]$Value) {
    $escapedValue = [regex]::Escape($Value)
    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    if ($Content -match $pattern) {
        return [regex]::Replace($Content, $pattern, "$Key=$Value")
    }

    $trimmed = $Content.TrimEnd("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return "$Key=$Value`r`n"
    }

    return $trimmed + "`r`n$Key=$Value`r`n"
}

function Initialize-MulticaEnv {
    $root = Get-HarnessRoot
    $config = Get-StackConfig
    $template = Join-Path $root 'config/multica.env.template'
    $target = Join-Path $root 'repos/multica/.env'
    if (-not (Test-Path $template)) { throw "Template missing: $template" }

    if (-not (Test-Path $target)) {
        Copy-Item $template $target
        Write-Good 'Created Multica .env from template'
    }
    else {
        Write-Info 'Multica .env already exists; syncing managed ports and URLs'
    }

    $content = Get-Content $target -Raw
    $databaseUrl = "postgres://multica:multica@localhost:$($config.ports.postgres)/multica?sslmode=disable"
    $frontendUrl = $config.urls.multicaFrontend

    $content = Set-DotEnvValue $content 'DATABASE_URL' $databaseUrl
    $content = Set-DotEnvValue $content 'FRONTEND_ORIGIN' $frontendUrl
    $content = Set-DotEnvValue $content 'CORS_ALLOWED_ORIGINS' $frontendUrl
    $content = Set-DotEnvValue $content 'PORT' ([string]$config.ports.multicaBackend)
    $content = Set-DotEnvValue $content 'FRONTEND_PORT' ([string]$config.ports.multicaFrontend)

    Set-Content -Path $target -Value $content -Encoding UTF8
}

function Test-MulticaEnvComplete {
    $envFile = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
    if (-not (Test-Path $envFile)) { return $false }
    $content = Get-Content $envFile -Raw
    return ($content -match 'RESEND_API_KEY=.+' -and $content -notmatch 'RESEND_API_KEY=\s*$' -and
            $content -match 'RESEND_FROM_EMAIL=.+' -and $content -notmatch 'RESEND_FROM_EMAIL=\s*$')
}
