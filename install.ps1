# Mitori Agent Install Script (Windows)
# Usage: $env:MITORI_INSTALL_TOKEN = "<token>"; irm https://raw.githubusercontent.com/mitori-app/mitori-agent/main/install.ps1 | iex
#    or: $env:MITORI_INSTALL_TOKEN = "<token>"; .\install.ps1
#
# What this script does:
#   1. Detects system architecture
#   2. Downloads the latest release from GitHub
#   3. Calls the Mitori registration API using the one-time install token
#   4. Writes the hostId + config to %ProgramData%\Mitori\config.yaml
#   5. Stores the host API key in a secure file
#   6. Installs and starts the agent as a Windows service
#
# After running this script, the agent will be running as a Windows service.
# Requires: PowerShell 5+ and Administrator privileges.

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ──────────────────────────────────────────────────────────────

$MitoriApiUrl     = if ($env:MITORI_API_URL) { $env:MITORI_API_URL } else { 'https://app.mitori.dev' }
$RegisterEndpoint = "$MitoriApiUrl/api/register"
$GitHubRepo       = 'mitori-app/mitori-agent'
$GitHubReleaseUrl = "https://github.com/$GitHubRepo/releases/latest/download"
$InstallDir       = Join-Path $env:ProgramFiles 'Mitori'
$BinaryName       = 'mitori-agent.exe'

# Config file paths
$ConfigDir  = Join-Path $env:ProgramData 'Mitori'
$ConfigFile = Join-Path $ConfigDir 'config.yaml'
$SecretFile = Join-Path $ConfigDir 'token'

# ── Helpers ────────────────────────────────────────────────────────────────────

function Write-Green  { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Yellow { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Red    { param($msg) Write-Host $msg -ForegroundColor Red }

function Exit-Error {
  param($msg)
  Write-Red "Error: $msg"
  exit 1
}

# ── Checks ─────────────────────────────────────────────────────────────────────

if (-not $env:MITORI_INSTALL_TOKEN) {
  Exit-Error @"
MITORI_INSTALL_TOKEN environment variable is not set.

Get your install command from the Mitori dashboard (Add Server), then run:
  `$env:MITORI_INSTALL_TOKEN = '<token>'
  .\install.ps1
"@
}

# ── Detect Architecture ────────────────────────────────────────────────────────

$Arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { Exit-Error 'Only 64-bit Windows is supported' }

# ── Download Latest Release ────────────────────────────────────────────────────

Write-Host 'Downloading latest Mitori agent...' -ForegroundColor Cyan

$BinaryFilename = "mitori-agent-windows-$Arch.exe"
$DownloadUrl    = "$GitHubReleaseUrl/$BinaryFilename"
$ChecksumUrl    = "$DownloadUrl.sha256"

Write-Host "Downloading $BinaryFilename..."

# Create temp directory
$TempDir = Join-Path $env:TEMP "mitori-install-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
  # Download binary
  $TempBinary = Join-Path $TempDir $BinaryName
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempBinary -UseBasicParsing -TimeoutSec 60

  # Download checksum
  $TempChecksum = Join-Path $TempDir 'checksum.sha256'
  Invoke-WebRequest -Uri $ChecksumUrl -OutFile $TempChecksum -UseBasicParsing -TimeoutSec 15

  # Verify checksum
  Write-Host 'Verifying checksum...'
  $ExpectedHash = (Get-Content $TempChecksum).Split(' ')[0]
  $ActualHash = (Get-FileHash -Path $TempBinary -Algorithm SHA256).Hash.ToLower()

  if ($ExpectedHash -ne $ActualHash) {
    Exit-Error 'Checksum verification failed'
  }

  Write-Green '✓ Binary downloaded and verified'

  # Install binary
  if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  }

  $FinalBinary = Join-Path $InstallDir $BinaryName

  # Stop service if running
  $ServiceName = 'MitoriAgent'
  $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  if ($Service) {
    Write-Host 'Stopping existing service...'
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  Copy-Item -Path $TempBinary -Destination $FinalBinary -Force
  Write-Green '✓ Binary installed'

} finally {
  Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Existing Config? (preserve hostId on re-install) ──────────────────────────

$ExistingHostId = $null
if (Test-Path $ConfigFile) {
  $ConfigContent = Get-Content $ConfigFile -Raw
  if ($ConfigContent -match 'hostId:\s*"([^"]+)"') {
    $ExistingHostId = $Matches[1]
    Write-Yellow "Existing config found at $ConfigFile."
    Write-Yellow "Re-registering host $ExistingHostId with a new token..."
  } else {
    Write-Yellow "Config file found but could not read hostId. Registering as a new host."
  }
}

# ── Get Hostname ───────────────────────────────────────────────────────────────

$HostHostname = $env:COMPUTERNAME
Write-Host "Registering host: $HostHostname" -ForegroundColor Cyan

# ── Call Registration API ──────────────────────────────────────────────────────

Write-Host "Contacting Mitori API at $RegisterEndpoint ..."

$Headers = @{
  'Authorization' = "Bearer $env:MITORI_INSTALL_TOKEN"
  'Content-Type'  = 'application/json'
}

# Build JSON body — include hostId when re-registering an existing host
if ($ExistingHostId) {
  $Body = [System.Text.Encoding]::UTF8.GetBytes("{`"hostname`": `"$HostHostname`", `"hostId`": `"$ExistingHostId`"}")
} else {
  $Body = [System.Text.Encoding]::UTF8.GetBytes("{`"hostname`": `"$HostHostname`"}")
}

try {
  $Response = Invoke-WebRequest `
    -Uri $RegisterEndpoint `
    -Method POST `
    -Headers $Headers `
    -Body $Body `
    -UseBasicParsing `
    -TimeoutSec 15
} catch {
  $StatusCode = $_.Exception.Response.StatusCode.value__
  $ResponseBody = $_.ErrorDetails.Message

  if ($StatusCode -eq 404 -and $ExistingHostId) {
    Write-Yellow "Host $ExistingHostId not found in Mitori. Clearing config and registering as a new host..."
    Remove-Item -Path $ConfigFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $SecretFile -Force -ErrorAction SilentlyContinue
    $ExistingHostId = $null
    $Body = [System.Text.Encoding]::UTF8.GetBytes("{`"hostname`": `"$HostHostname`"}")
    try {
      $Response = Invoke-WebRequest `
        -Uri $RegisterEndpoint `
        -Method POST `
        -Headers $Headers `
        -Body $Body `
        -UseBasicParsing `
        -TimeoutSec 15
    } catch {
      $StatusCode = $_.Exception.Response.StatusCode.value__
      $ResponseBody = $_.ErrorDetails.Message
      Exit-Error "Registration failed (HTTP $StatusCode): $ResponseBody"
    }
  } else {
    Exit-Error "Registration failed (HTTP $StatusCode): $ResponseBody"
  }
}

if ($Response.StatusCode -ne 200) {
  Exit-Error "Registration failed (HTTP $($Response.StatusCode)): $($Response.Content)"
}

# ── Parse Response ─────────────────────────────────────────────────────────────

$Parsed = $Response.Content | ConvertFrom-Json
$HostId      = $Parsed.hostId
$HostApiKey  = $Parsed.hostApiKey
$IngestorUrl = $Parsed.ingestorUrl

if (-not $HostId -or -not $HostApiKey -or -not $IngestorUrl) {
  Exit-Error "Failed to parse hostId/hostApiKey/ingestorUrl from API response: $($Response.Content)"
}

# ── Write Config File ──────────────────────────────────────────────────────────

if (-not (Test-Path $ConfigDir)) {
  New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Restrict config dir to Administrators + SYSTEM only
$Acl = New-Object System.Security.AccessControl.DirectorySecurity
$Acl.SetAccessRuleProtection($true, $false)
$AdminRule  = New-Object System.Security.AccessControl.FileSystemAccessRule(
  'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$Acl.AddAccessRule($AdminRule)
$Acl.AddAccessRule($SystemRule)
Set-Acl -Path $ConfigDir -AclObject $Acl

$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

@"
# Mitori Agent Configuration
# Generated on $Timestamp by the install script.
# Do not edit hostId - it identifies this server in Mitori.

hostId: "$HostId"
hostname: "$HostHostname"
ingestorUrl: "$IngestorUrl"
"@ | Set-Content -Path $ConfigFile -Encoding UTF8

# ── Write Secret File ──────────────────────────────────────────────────────────

$HostApiKey | Set-Content -Path $SecretFile -NoNewline -Encoding UTF8

# Restrict secret file to Administrators + SYSTEM only
$Acl = New-Object System.Security.AccessControl.FileSecurity
$Acl.SetAccessRuleProtection($true, $false)
$AdminRule  = New-Object System.Security.AccessControl.FileSystemAccessRule(
  'BUILTIN\Administrators', 'FullControl', 'None', 'None', 'Allow')
$SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  'NT AUTHORITY\SYSTEM', 'FullControl', 'None', 'None', 'Allow')
$Acl.AddAccessRule($AdminRule)
$Acl.AddAccessRule($SystemRule)
Set-Acl -Path $SecretFile -AclObject $Acl

# ── Install Windows Service ────────────────────────────────────────────────────

Write-Host 'Installing Windows service...' -ForegroundColor Cyan

$ServiceName = 'MitoriAgent'
$ServiceDisplayName = 'Mitori Monitoring Agent'
$ServiceDescription = 'Collects system metrics and sends them to Mitori'

# Remove existing service if it exists
$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($ExistingService) {
  Write-Host 'Removing existing service...'
  Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  sc.exe delete $ServiceName | Out-Null
  Start-Sleep -Seconds 1
}

# Create new service using sc.exe (New-Service doesn't support auto-restart)
$BinaryPath = Join-Path $InstallDir $BinaryName
sc.exe create $ServiceName binPath= $BinaryPath start= auto DisplayName= $ServiceDisplayName | Out-Null

if ($LASTEXITCODE -ne 0) {
  Exit-Error "Failed to create Windows service"
}

# Set service description
sc.exe description $ServiceName $ServiceDescription | Out-Null

# Configure service to restart on failure
sc.exe failure $ServiceName reset= 86400 actions= restart/10000/restart/10000/restart/10000 | Out-Null

# Start the service
Write-Host 'Starting service...'
Start-Service -Name $ServiceName

Write-Green '✓ Service installed and started'
Write-Host "  Status: Get-Service -Name $ServiceName"
Write-Host "  Logs:   Get-EventLog -LogName Application -Source $ServiceName -Newest 50"

# ── Done ───────────────────────────────────────────────────────────────────────

Write-Green ""
if ($ExistingHostId) {
  Write-Green "✓ Mitori agent installed and running! (hostId preserved)"
} else {
  Write-Green "✓ Mitori agent installed and running!"
}
Write-Green ""
Write-Host "  Host ID    : $HostId"
Write-Host "  Config     : $ConfigFile"
Write-Host "  Token file : $SecretFile"
Write-Host "  Binary     : $BinaryPath"
Write-Green ""
Write-Host "The agent is now running as a Windows service and will start automatically on boot."
