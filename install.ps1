<#
.SYNOPSIS
  Forge plugin installer for Windows (PowerShell 5.1+ / 7.x).

.DESCRIPTION
  Clones quantumbitcz/forge into $env:USERPROFILE\.claude\plugins\forge and
  adds the plugin path to settings.json. macOS/Linux users: use install.sh.

.PARAMETER Help
  Print usage and exit.

.PARAMETER WhatIf
  Print planned actions without writing anything.

.PARAMETER Repo
  Git URL to clone (default: https://github.com/quantumbitcz/forge.git).

.PARAMETER Ref
  Git ref to check out (default: master).

.PARAMETER PluginDir
  Install destination (default: $env:USERPROFILE\.claude\plugins\forge).
#>
param(
    [switch]$Help,
    [switch]$WhatIf,
    [string]$Repo = 'https://github.com/quantumbitcz/forge.git',
    [string]$Ref  = 'master',
    [string]$PluginDir = (Join-Path $env:USERPROFILE '.claude\plugins\forge')
)

$ErrorActionPreference = 'Stop'
$InformationPreference  = 'Continue'

function Write-Info { param([string]$m) Write-Information "[install.ps1] $m" }

if ($Help) {
    @'
Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-WhatIf] [-Help]
                                                          [-Repo <url>]
                                                          [-Ref  <ref>]
                                                          [-PluginDir <path>]

Installs the forge plugin into $env:USERPROFILE\.claude\plugins\forge.
'@ | Write-Information
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw '[install.ps1] git is required but not found in PATH'
}

$settingsDir  = Join-Path $env:USERPROFILE '.claude'
$settingsFile = Join-Path $settingsDir 'settings.json'

if ($WhatIf) {
    Write-Info "dry-run: would ensure $PluginDir exists"
    Write-Info "dry-run: would clone $Repo ref $Ref into $PluginDir"
    Write-Info "dry-run: would merge plugin entry into $settingsFile"
    exit 0
}

if (-not (Test-Path -LiteralPath (Split-Path $PluginDir -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $PluginDir -Parent) -Force | Out-Null
}

if (Test-Path -LiteralPath (Join-Path $PluginDir '.git')) {
    Write-Info "updating existing clone at $PluginDir"
    git -C $PluginDir fetch --depth 1 origin $Ref
    git -C $PluginDir checkout $Ref
    git -C $PluginDir reset --hard "origin/$Ref"
} else {
    Write-Info "cloning $Repo into $PluginDir"
    git clone --depth 1 --branch $Ref $Repo $PluginDir
}

if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $settingsFile)) {
    @{ plugins = @($PluginDir) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    Write-Info "created $settingsFile with plugin entry"
} else {
    $raw = Get-Content -LiteralPath $settingsFile -Raw
    if ($raw -match [regex]::Escape($PluginDir)) {
        Write-Info "$settingsFile already references $PluginDir"
    } else {
        Write-Warning "[install.ps1] $settingsFile exists; add `"$PluginDir`" to its 'plugins' array manually"
    }
}

Write-Info 'done. Run /forge in a project to complete setup.'
