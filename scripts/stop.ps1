param(
    [switch]$IncludeMultica
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/agentchattr.ps1')

if ($IncludeMultica) {
    Invoke-Step 'Stop local Multica processes' {
        Stop-MulticaProcesses
    }

    Invoke-Step 'Stop Multica daemon' {
        Stop-MulticaDaemon
    }
} else {
    Write-Info 'Skipping Multica shutdown (use -IncludeMultica to enable)'
}

Invoke-Step 'Stop pi-agentchattr worker' {
    Stop-PiAgentchattrWorker
}

Invoke-Step 'Stop agentchattr' {
    Stop-Agentchattr
}

Invoke-Step 'Stop docker infrastructure' {
    Stop-Infrastructure
}

Write-Good 'Stopped harness-managed services'
