# Mitori Agent Uninstall Script (Windows)
# Usage: irm https://raw.githubusercontent.com/mitori-app/mitori-agent/main/uninstall.ps1 | iex
#    or: .\uninstall.ps1
#
# What this script does:
#   1. Stops the Mitori agent Windows service
#   2. Removes the Windows service
#   3. Removes the binary from Program Files
#   4. Optionally removes config files and tokens
#
# Requires: PowerShell 5+ and Administrator privileges.

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ──────────────────────────────────────────────────────────────

$InstallDir  = Join-Path $env:ProgramFiles 'Mitori'
$BinaryName  = 'mitori-agent.exe'
$ConfigDir   = Join-Path $env:ProgramData 'Mitori'
$ConfigFile  = Join-Path $ConfigDir 'config.yaml'
$SecretFile  = Join-Path $ConfigDir 'token'
$ServiceName = 'MitoriAgent'

# ── Helpers ────────────────────────────────────────────────────────────────────

function Write-Green  { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Yellow { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Red    { param($msg) Write-Host $msg -ForegroundColor Red }

function Exit-Error {
  param($msg)
  Write-Red "Error: $msg"
  exit 1
}

# ── Uninstall ──────────────────────────────────────────────────────────────────

Write-Host 'Uninstalling Mitori agent...' -ForegroundColor Cyan

# Stop and remove Windows service
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($Service) {
  Write-Host 'Stopping Windows service...'
  Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2

  Write-Host 'Removing Windows service...'
  sc.exe delete $ServiceName | Out-Null

  if ($LASTEXITCODE -eq 0) {
    Write-Green '✓ Service removed'
  } else {
    Write-Yellow 'Warning: Failed to remove service (may require manual removal)'
  }
} else {
  Write-Yellow 'Service not found, skipping'
}

# Wait a moment for service to fully stop
Start-Sleep -Seconds 2

# Remove binary
$BinaryPath = Join-Path $InstallDir $BinaryName
if (Test-Path $BinaryPath) {
  Write-Host 'Removing binary...'
  try {
    Remove-Item -Path $BinaryPath -Force
    Write-Green '✓ Binary removed'
  } catch {
    Write-Yellow "Warning: Could not remove binary (file may be in use): $_"
  }
} else {
  Write-Yellow 'Binary not found, skipping'
}

# Remove install directory if empty
if (Test-Path $InstallDir) {
  $Items = Get-ChildItem -Path $InstallDir -ErrorAction SilentlyContinue
  if ($Items.Count -eq 0) {
    Remove-Item -Path $InstallDir -Force -ErrorAction SilentlyContinue
  }
}

# Ask about config files
if (Test-Path $ConfigDir) {
  Write-Host ''
  Write-Yellow "Configuration directory found: $ConfigDir"
  Write-Host 'This contains your host ID and API token.'

  $response = Read-Host 'Remove configuration files? [y/N]'

  if ($response -match '^[Yy]$') {
    Write-Host 'Removing configuration...'
    try {
      Remove-Item -Path $ConfigDir -Recurse -Force
      Write-Green '✓ Configuration removed'
    } catch {
      Write-Yellow "Warning: Could not remove configuration: $_"
    }
  } else {
    Write-Yellow "Configuration preserved at $ConfigDir"
    Write-Host "  To remove manually later: Remove-Item -Path '$ConfigDir' -Recurse -Force"
  }
} else {
  Write-Yellow 'Configuration directory not found, skipping'
}

# ── Done ───────────────────────────────────────────────────────────────────────

Write-Green ''
Write-Green '✓ Mitori agent uninstalled successfully!'
Write-Green ''
Write-Host 'The agent has been removed from your system.'

# Check if process is still running
$Process = Get-Process -Name 'mitori-agent' -ErrorAction SilentlyContinue
if ($Process) {
  Write-Host ''
  Write-Yellow 'Warning: A mitori-agent process is still running.'
  Write-Yellow "You may need to manually stop it: Stop-Process -Name 'mitori-agent' -Force"
}
