<#
.SYNOPSIS
  PowerShell wrapper around tests/run-all.sh for Windows pwsh coverage.
#>
param(
    [Parameter(Position = 0)]
    [string]$Tier = 'all'
)

$ErrorActionPreference = 'Stop'

$bash = (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bash) {
    $candidate = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    if (Test-Path -LiteralPath $candidate) {
        $bash = @{ Source = $candidate }
    } else {
        Write-Error 'bash.exe not found (install Git for Windows or WSL)'
    }
}

$script = Join-Path $PSScriptRoot 'run-all.sh'
& $bash.Source $script $Tier
exit $LASTEXITCODE
