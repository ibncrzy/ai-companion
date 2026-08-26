<#
.SYNOPSIS
  Repackage the unpacked mod source into the zip Factorio actually loads.

.DESCRIPTION
  Factorio loads mods\ai-companion_0.13.0.zip, NOT this git working copy directly (it only scans
  one level under mods\ for info.json, and this repo's own info.json sits two levels deeper than
  that due to the nested ai-companion_0.13.0\ai-companion_0.13.0\ai-companion_0.13.0 layout). Every
  edit to control.lua/commands/*.lua etc. is invisible to a running game until this zip is
  regenerated AND Factorio is fully restarted (not just save-reloaded) - the zip file is locked
  while Factorio is running, so this must be run with Factorio closed.

  See CLAUDE.md's "Install/deploy the mod" section and KNOWN_ISSUES.md's mod-packaging entries for
  the full story (including a real incident where an unpushed fix sat un-loaded for a while because
  of exactly this).

.EXAMPLE
  .\deploy.ps1
#>

$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path $PSScriptRoot 'ai-companion_0.13.0'
$destZip = Join-Path $env:APPDATA 'Factorio\mods\ai-companion_0.13.0.zip'

if (-not (Test-Path $sourceDir)) {
    Write-Error "Source folder not found: $sourceDir"
    exit 1
}

try {
    Compress-Archive -Path $sourceDir -DestinationPath $destZip -Force
    Write-Host "Deployed: $destZip"
    Write-Host "Restart Factorio (fully close and reopen - a save reload is not enough) for changes to take effect."
}
catch {
    if ($_.Exception.Message -match 'being used by another process|cannot access the file') {
        Write-Error "Zip is locked - Factorio is probably still running. Close it fully, then re-run this script."
    }
    else {
        throw
    }
}
