. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/env.ps1')

$config = Get-StackConfig

Write-Section 'CLI tools'
foreach ($cmd in @('git','python','node','pnpm','go','docker','claude','codex')) {
    if (Test-CommandExists $cmd) { Write-Good "$cmd found" } else { Write-Warn "$cmd missing" }
}

Write-Section 'Ports'
foreach ($pair in @(
    @{ Name='Postgres'; Port=$config.ports.postgres },
    @{ Name='SearXNG'; Port=$config.ports.searxng },
    @{ Name='Multica backend'; Port=$config.ports.multicaBackend },
    @{ Name='Multica frontend'; Port=$config.ports.multicaFrontend }
)) {
    if (Test-TcpPort '127.0.0.1' $pair.Port) { Write-Good "$($pair.Name) listening on $($pair.Port)" } else { Write-Warn "$($pair.Name) not listening on $($pair.Port)" }
}

Write-Section 'HTTP health'
foreach ($u in @($config.urls.searxng, $config.urls.multicaBackendHealth, $config.urls.multicaFrontend)) {
    if (Test-HttpOk $u) { Write-Good "$u reachable" } else { Write-Warn "$u not reachable" }
}

Write-Section 'Config state'
$multicaEnv = Join-Path (Get-HarnessRoot) 'repos/multica/.env'
if (Test-Path $multicaEnv) { Write-Good 'Multica .env exists' } else { Write-Warn 'Multica .env missing' }
if (Test-MulticaEnvComplete) { Write-Good 'Multica Resend settings appear filled' } else { Write-Warn 'Multica Resend settings incomplete' }

Write-Section 'Docker containers'
foreach ($c in @('postgres','searxng')) {
    if (Test-DockerServiceRunning $c) { Write-Good "$c running" } else { Write-Warn "$c not running" }
}
