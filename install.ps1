<#
.SYNOPSIS
  One-time setup so you can run `ai-lore` from any project in PowerShell.

.DESCRIPTION
  - Allows local scripts to run for your user (no admin needed).
  - Adds an `ai-lore` command to your PowerShell profile.
  Re-running is safe; it just refreshes the command.

  Easiest way to run: right-click this file -> "Run with PowerShell".
  Or from a terminal:  powershell -ExecutionPolicy Bypass -File install.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $PSCommandPath
$Launcher = Join-Path $RepoDir "bin\ai-lore.ps1"

if (-not (Test-Path $Launcher)) {
  Write-Host "install: cannot find $Launcher" -ForegroundColor Red
  exit 1
}

# 1) Let signed/local scripts run for this user (no admin required).
try {
  $cur = Get-ExecutionPolicy -Scope CurrentUser
  if ($cur -eq "Restricted" -or $cur -eq "Undefined" -or $cur -eq "AllSigned") {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host "install: set execution policy (CurrentUser) to RemoteSigned."
  }
}
catch {
  Write-Host "install: could not set execution policy automatically: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 2) Add an `ai-lore` function to the user's PowerShell profile (idempotent).
$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $profilePath
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Force -Path $profilePath | Out-Null }

$begin = "# >>> ai-lore >>>"
$end = "# <<< ai-lore <<<"
$block = @"
$begin
function ai-lore { & "$Launcher" @args }
$end
"@

$content = Get-Content -Raw -Path $profilePath -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = "" }

if ($content -match [regex]::Escape($begin)) {
  # Replace existing block.
  $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
  $content = [regex]::Replace($content, $pattern, $block)
  Set-Content -Path $profilePath -Value $content -Encoding UTF8
  Write-Host "install: refreshed ai-lore command in $profilePath"
}
else {
  Add-Content -Path $profilePath -Value "`r`n$block`r`n"
  Write-Host "install: added ai-lore command to $profilePath"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Open a NEW PowerShell window, then:"
Write-Host "  1) cd into one of your projects"
Write-Host "  2) run:  ai-lore setup"
Write-Host ""
Write-Host "(This terminal won't have the command yet - only new windows pick up the profile.)"
