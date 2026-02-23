#!/usr/bin/env bash
# Mitori Agent Install Script (Linux + macOS)
# Usage: MITORI_INSTALL_TOKEN=<token> curl -sSL https://raw.githubusercontent.com/mitori-app/mitori-agent/main/install.sh | sudo -E bash
#    or: MITORI_INSTALL_TOKEN=<token> sudo -E bash install.sh
#
# Get your install token from the Mitori dashboard (Add Server).
# The token expires in 3 minutes and is single-use.
#
# What this script does:
#   1. Detects the OS and architecture
#   2. Downloads the latest release from GitHub
#   3. Calls the Mitori registration API using the one-time install token
#   4. Writes the hostId to a config file
#   5. Writes the returned host API key to a secret file (root-only permissions)
#   6. Installs and starts the agent as a system service
#
# After running this script, the agent will be running as a system service.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

MITORI_API_URL="${MITORI_API_URL:-https://app.mitori.dev}"
REGISTER_ENDPOINT="${MITORI_API_URL}/api/register"
GITHUB_REPO="mitori-app/mitori-agent"
GITHUB_RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="mitori-agent"

# ── Helpers ───────────────────────────────────────────────────────────────────

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

die() { red "Error: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

# ── Checks ────────────────────────────────────────────────────────────────────

require_cmd curl
require_cmd hostname

if [[ -z "${MITORI_INSTALL_TOKEN:-}" ]]; then
  die "MITORI_INSTALL_TOKEN is not set.

  Get your install command from the Mitori dashboard (Add Server), then run:
    MITORI_INSTALL_TOKEN=<token> sudo -E bash install.sh"
fi

# ── OS Detection + Path Setup ─────────────────────────────────────────────────

OS="$(uname -s)"

case "$OS" in
  Linux)
    CONFIG_DIR="/etc/mitori"
    CONFIG_FILE="${CONFIG_DIR}/config.yaml"
    SECRET_FILE="${CONFIG_DIR}/token"
    ;;
  Darwin)
    CONFIG_DIR="/Library/Application Support/Mitori"
    CONFIG_FILE="${CONFIG_DIR}/config.yaml"
    SECRET_FILE="${CONFIG_DIR}/token"
    ;;
  *)
    die "Unsupported OS: $OS. Please use the Windows install script for Windows."
    ;;
esac

# ── Root check ────────────────────────────────────────────────────────────────

if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root (sudo) to write to ${CONFIG_DIR}."
fi

# ── Detect Architecture ───────────────────────────────────────────────────────

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    ;;
  *)
    die "Unsupported architecture: $ARCH. Supported: x86_64, aarch64/arm64."
    ;;
esac

# ── Download Latest Release ───────────────────────────────────────────────────

bold "Downloading latest Mitori agent..."

OS_LOWER="$(echo "$OS" | tr '[:upper:]' '[:lower:]')"
BINARY_FILENAME="mitori-agent-${OS_LOWER}-${ARCH}"
DOWNLOAD_URL="${GITHUB_RELEASE_URL}/${BINARY_FILENAME}"
CHECKSUM_URL="${DOWNLOAD_URL}.sha256"

printf 'Downloading %s...\n' "$BINARY_FILENAME"

# Create temp directory
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Download binary
curl -sSL --max-time 60 -o "${TEMP_DIR}/${BINARY_NAME}" "${DOWNLOAD_URL}" || \
  die "Failed to download binary from ${DOWNLOAD_URL}"

# Download and verify checksum
curl -sSL --max-time 15 -o "${TEMP_DIR}/${BINARY_NAME}.sha256" "${CHECKSUM_URL}" || \
  die "Failed to download checksum"

printf 'Verifying checksum...\n'
(cd "$TEMP_DIR" && sha256sum -c "${BINARY_NAME}.sha256" 2>/dev/null | grep -q OK) || \
  die "Checksum verification failed"

green "✓ Binary downloaded and verified"

# Install binary
printf 'Installing to %s/%s...\n' "$INSTALL_DIR" "$BINARY_NAME"
install -m 755 "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"

green "✓ Binary installed"

# ── Existing Config? (preserve hostId on re-install) ─────────────────────────

EXISTING_HOST_ID=""
if [[ -f "$CONFIG_FILE" ]]; then
  EXISTING_HOST_ID="$(grep -o 'hostId: *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f2 || true)"
  if [[ -n "$EXISTING_HOST_ID" ]]; then
    yellow "Existing config found at ${CONFIG_FILE}."
    yellow "Re-registering host ${EXISTING_HOST_ID} with a new token..."
  else
    yellow "Config file found but could not read hostId. Registering as a new host."
  fi
fi

# ── Get Hostname ──────────────────────────────────────────────────────────────

HOST_HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
bold "Registering host: ${HOST_HOSTNAME}"

# ── Call Registration API ─────────────────────────────────────────────────────

printf 'Contacting Mitori API at %s ...\n' "$REGISTER_ENDPOINT"

# Build JSON body — include hostId when re-registering an existing host
if [[ -n "$EXISTING_HOST_ID" ]]; then
  REQUEST_BODY="{\"hostname\": \"${HOST_HOSTNAME}\", \"hostId\": \"${EXISTING_HOST_ID}\"}"
else
  REQUEST_BODY="{\"hostname\": \"${HOST_HOSTNAME}\"}"
fi

HTTP_RESPONSE="$(curl -sS \
  --max-time 15 \
  -X POST \
  -H "Authorization: Bearer ${MITORI_INSTALL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY" \
  -w "\n%{http_code}" \
  "${REGISTER_ENDPOINT}")"

HTTP_STATUS="$(echo "$HTTP_RESPONSE" | tail -n 1)"
HTTP_BODY="$(echo "$HTTP_RESPONSE" | sed '$d')"

if [[ "$HTTP_STATUS" == "401" ]]; then
  die "Invalid or expired install token. Go back to the Mitori dashboard and generate a new install command."
elif [[ "$HTTP_STATUS" == "404" && -n "$EXISTING_HOST_ID" ]]; then
  yellow "Host ${EXISTING_HOST_ID} not found in Mitori. Clearing config and registering as a new host..."
  rm -f "$CONFIG_FILE" "$SECRET_FILE"
  EXISTING_HOST_ID=""
  REQUEST_BODY="{\"hostname\": \"${HOST_HOSTNAME}\"}"
  HTTP_RESPONSE="$(curl -sS \
    --max-time 15 \
    -X POST \
    -H "Authorization: Bearer ${MITORI_INSTALL_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    -w "\n%{http_code}" \
    "${REGISTER_ENDPOINT}")"
  HTTP_STATUS="$(echo "$HTTP_RESPONSE" | tail -n 1)"
  HTTP_BODY="$(echo "$HTTP_RESPONSE" | sed '$d')"
  if [[ "$HTTP_STATUS" == "401" ]]; then
    die "Invalid or expired install token. Go back to the Mitori dashboard and generate a new install command."
  elif [[ "$HTTP_STATUS" != "200" ]]; then
    die "Registration failed (HTTP ${HTTP_STATUS}): ${HTTP_BODY}"
  fi
elif [[ "$HTTP_STATUS" != "200" ]]; then
  die "Registration failed (HTTP ${HTTP_STATUS}): ${HTTP_BODY}"
fi

# ── Parse Response ────────────────────────────────────────────────────────────

# Minimal JSON parsing without jq dependency
HOST_ID="$(echo "$HTTP_BODY" | grep -o '"hostId":"[^"]*"' | cut -d'"' -f4)"
HOST_API_KEY="$(echo "$HTTP_BODY" | grep -o '"hostApiKey":"[^"]*"' | cut -d'"' -f4)"
INGESTOR_URL="$(echo "$HTTP_BODY" | grep -o '"ingestorUrl":"[^"]*"' | cut -d'"' -f4)"

if [[ -z "$HOST_ID" || -z "$HOST_API_KEY" || -z "$INGESTOR_URL" ]]; then
  die "Failed to parse response from API: ${HTTP_BODY}"
fi

# ── Write Config File ─────────────────────────────────────────────────────────

mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
# Mitori Agent Configuration
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ") by the install script.
# Do not edit hostId - it identifies this server in Mitori.

hostId: "${HOST_ID}"
hostname: "${HOST_HOSTNAME}"
ingestorUrl: "${INGESTOR_URL}"
EOF

chmod 644 "$CONFIG_FILE"

# ── Write Secret File ─────────────────────────────────────────────────────────

printf '%s' "${HOST_API_KEY}" > "$SECRET_FILE"

# Readable only by root — the agent must run as root or a dedicated service user
chmod 600 "$SECRET_FILE"

# ── Install System Service ───────────────────────────────────────────────────

bold "Installing system service..."

case "$OS" in
  Linux)
    # Create systemd service file
    SERVICE_FILE="/etc/systemd/system/mitori-agent.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Mitori Monitoring Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${BINARY_NAME}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mitori-agent

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable mitori-agent.service
    systemctl restart mitori-agent.service

    green "✓ Service installed and started"
    printf '  Status: systemctl status mitori-agent\n'
    printf '  Logs:   journalctl -u mitori-agent -f\n'
    ;;

  Darwin)
    # Create LaunchDaemon plist
    PLIST_FILE="/Library/LaunchDaemons/dev.mitori.agent.plist"
    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.mitori.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${BINARY_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/mitori-agent.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/mitori-agent.log</string>
</dict>
</plist>
EOF

    chmod 644 "$PLIST_FILE"

    # Load and start service
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"

    green "✓ Service installed and started"
    printf '  Status: launchctl list | grep mitori\n'
    printf '  Logs:   tail -f /var/log/mitori-agent.log\n'
    ;;
esac

# ── Done ──────────────────────────────────────────────────────────────────────

green ""
if [[ -n "$EXISTING_HOST_ID" ]]; then
  green "✓ Mitori agent installed and running! (hostId preserved)"
else
  green "✓ Mitori agent installed and running!"
fi
green ""
printf '  Host ID    : %s\n' "$HOST_ID"
printf '  Config     : %s\n' "$CONFIG_FILE"
printf '  Token file : %s\n' "$SECRET_FILE"
printf '  Binary     : %s/%s\n' "$INSTALL_DIR" "$BINARY_NAME"
green ""
printf 'The agent is now running as a system service and will start automatically on boot.\n'
