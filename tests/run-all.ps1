<#
.SYNOPSIS
  PowerShell wrapper around tests/run-all.sh for Windows pwsh coverage.
#>
param(
    [Parameter(Position = 0)]
    [string]$Tier = 'all'
)

$ErrorActionPreference = 'Stop'

# Probe order: PATH -> %ProgramFiles%\Git -> %ProgramW6432%\Git (64-bit on
# 32-bit OS) -> %ProgramFiles(x86)%\Git -> WSL fallback.
$probed = @()
$bashSource = $null

$onPath = Get-Command bash -ErrorAction SilentlyContinue
if ($onPath) {
    $bashSource = $onPath.Source
}

if (-not $bashSource) {
    $candidates = @()
    if ($env:ProgramFiles)        { $candidates += (Join-Path $env:ProgramFiles        'Git\bin\bash.exe') }
    if ($env:ProgramW6432)        { $candidates += (Join-Path $env:ProgramW6432        'Git\bin\bash.exe') }
    $x86 = ${env:ProgramFiles(x86)}
    if ($x86)                     { $candidates += (Join-Path $x86                     'Git\bin\bash.exe') }

    foreach ($c in $candidates) {
        $probed += $c
        if (Test-Path -LiteralPath $c) {
            $bashSource = $c
            break
        }
    }
}

# WSL fallback: invoke Linux bash via wsl.exe if available.
$useWsl = $false
if (-not $bashSource) {
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wsl) {
        $bashSource = $wsl.Source
        $useWsl = $true
    } else {
        $probed += 'wsl --exec bash'
    }
}

if (-not $bashSource) {
    $msg = "bash.exe not found. Probed:`n  PATH (via Get-Command bash)"
    foreach ($p in $probed) { $msg += "`n  $p" }
    $msg += "`nInstall Git for Windows, or enable WSL with a bash-providing distro."
    Write-Error $msg
    exit 1
}

$script = Join-Path $PSScriptRoot 'run-all.sh'
if ($useWsl) {
    & $bashSource --exec bash $script $Tier
} else {
    & $bashSource $script $Tier
}
exit $LASTEXITCODE
