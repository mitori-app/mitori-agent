# Mitori Agent Install Script (Windows)
# Usage: $env:MITORI_API_KEY = "<key>"; irm https://app.mitori.dev/install.ps1 | iex
#    or: $env:MITORI_API_KEY = "<key>"; .\install.ps1
#
# What this script does:
#   1. Calls the Mitori registration API to obtain a hostId + hostToken
#   2. Writes the hostId + config to %ProgramData%\Mitori\config.yaml
#   3. Stores the hostToken in Windows Credential Manager (readable by go-keyring)
#
# After running this script, start the agent binary. It will read these files automatically.
# Requires: PowerShell 5+ and Administrator privileges.

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ──────────────────────────────────────────────────────────────

$MitoriApiUrl    = if ($env:MITORI_API_URL) { $env:MITORI_API_URL } else { 'https://app.mitori.dev' }
$RegisterEndpoint = "$MitoriApiUrl/api/register"

# go-keyring stores credentials in Windows Credential Manager using this service name.
# The agent Go code must use the same service + username to retrieve the token.
$KeyringService  = 'mitori-agent'
$KeyringUsername = 'host-token'

# Config file path
$ConfigDir  = Join-Path $env:ProgramData 'Mitori'
$ConfigFile = Join-Path $ConfigDir 'config.yaml'

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

if (-not $env:MITORI_API_KEY) {
  Exit-Error @"
MITORI_API_KEY environment variable is not set.

Get your API key from the Mitori dashboard, then run:
  `$env:MITORI_API_KEY = '<your-key>'
  .\install.ps1
"@
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
  'Authorization' = "Bearer $env:MITORI_API_KEY"
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
    cmdkey /delete:"$KeyringService/$KeyringUsername" 2>$null | Out-Null
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
$HostToken   = $Parsed.hostToken
$IngestorUrl = $Parsed.ingestorUrl

if (-not $HostId -or -not $HostToken -or -not $IngestorUrl) {
  Exit-Error "Failed to parse hostId/hostToken/ingestorUrl from API response: $($Response.Content)"
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

# ── Store Token in Windows Credential Manager ──────────────────────────────────
# go-keyring reads from Windows Credential Manager using service + username as the target name.
# Target format used by go-keyring: "<service>/<username>"

$CredentialTarget = "$KeyringService/$KeyringUsername"

# Remove any existing credential for this target
cmdkey /delete:"$CredentialTarget" 2>$null | Out-Null

# Store the new token
$Result = cmdkey /generic:"$CredentialTarget" /user:"$KeyringUsername" /pass:"$HostToken"
if ($LASTEXITCODE -ne 0) {
  Exit-Error "Failed to store token in Windows Credential Manager: $Result"
}

# ── Done ───────────────────────────────────────────────────────────────────────

Write-Green ""
if ($ExistingHostId) {
  Write-Green "Mitori agent re-registered successfully! (hostId preserved)"
} else {
  Write-Green "Mitori agent registered successfully!"
}
Write-Green ""
Write-Host "  Host ID    : $HostId"
Write-Host "  Config     : $ConfigFile"
Write-Host "  Token      : stored in Windows Credential Manager ('$CredentialTarget')"
Write-Green ""
Write-Host "Next: start the Mitori agent binary to begin sending metrics."
