. (Join-Path $PSScriptRoot 'common.ps1')

function Initialize-MulticaEnv {
    $root = Get-HarnessRoot
    $template = Join-Path $root 'config/multica.env.template'
    $target = Join-Path $root 'repos/multica/.env'
    if (-not (Test-Path $template)) { throw "Template missing: $template" }
    if (-not (Test-Path $target)) {
        Copy-Item $template $target
        Write-Good 'Created Multica .env from template'
    }
    else {
        Write-Info 'Multica .env already exists'
    }
}

function Test-MulticaEnvComplete {
    $envFile = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
    if (-not (Test-Path $envFile)) { return $false }
    $content = Get-Content $envFile -Raw
    return ($content -match 'RESEND_API_KEY=.+' -and $content -notmatch 'RESEND_API_KEY=\s*$' -and
            $content -match 'RESEND_FROM_EMAIL=.+' -and $content -notmatch 'RESEND_FROM_EMAIL=\s*$')
}
