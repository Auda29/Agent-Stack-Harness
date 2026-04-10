. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/docker.ps1')
. (Join-Path $PSScriptRoot 'lib/multica.ps1')
. (Join-Path $PSScriptRoot 'lib/agentchattr.ps1')

Invoke-Step 'Stop local Multica processes' {
    Stop-MulticaProcesses
}

Invoke-Step 'Stop agentchattr' {
    Stop-Agentchattr
}

Invoke-Step 'Stop docker infrastructure' {
    Stop-Infrastructure
}

Write-Good 'Stopped harness-managed services'
