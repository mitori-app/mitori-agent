#!/usr/bin/env bash
# Mitori Agent Uninstall Script (Linux + macOS)
# Usage: sudo bash uninstall.sh
#    or: curl -sSL https://raw.githubusercontent.com/mitori-app/mitori-agent/main/uninstall.sh | sudo bash
#
# What this script does:
#   1. Stops the Mitori agent service
#   2. Removes the service configuration (LaunchDaemon/systemd)
#   3. Removes the binary from /usr/local/bin
#   4. Optionally removes config files and tokens

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="mitori-agent"

# ── Helpers ───────────────────────────────────────────────────────────────────

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

die() { red "Error: $*" >&2; exit 1; }

# ── OS Detection + Path Setup ─────────────────────────────────────────────────

OS="$(uname -s)"

case "$OS" in
  Linux)
    CONFIG_DIR="/etc/mitori"
    SERVICE_FILE="/etc/systemd/system/mitori-agent.service"
    ;;
  Darwin)
    CONFIG_DIR="/Library/Application Support/Mitori"
    SERVICE_FILE="/Library/LaunchDaemons/dev.mitori.agent.plist"
    ;;
  *)
    die "Unsupported OS: $OS. Please use the Windows uninstall script for Windows."
    ;;
esac

CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SECRET_FILE="${CONFIG_DIR}/token"

# ── Root check ────────────────────────────────────────────────────────────────

if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root (sudo) to remove system files."
fi

# ── Uninstall ─────────────────────────────────────────────────────────────────

bold "Uninstalling Mitori agent..."

# Stop and remove service
case "$OS" in
  Linux)
    if [[ -f "$SERVICE_FILE" ]]; then
      printf 'Stopping systemd service...\n'
      systemctl stop mitori-agent.service 2>/dev/null || true
      systemctl disable mitori-agent.service 2>/dev/null || true

      printf 'Removing service file...\n'
      rm -f "$SERVICE_FILE"
      systemctl daemon-reload

      green "✓ Service removed"
    else
      yellow "Service file not found, skipping"
    fi
    ;;

  Darwin)
    if [[ -f "$SERVICE_FILE" ]]; then
      printf 'Stopping LaunchDaemon...\n'
      launchctl unload "$SERVICE_FILE" 2>/dev/null || true

      printf 'Removing service file...\n'
      rm -f "$SERVICE_FILE"

      green "✓ Service removed"
    else
      yellow "Service file not found, skipping"
    fi
    ;;
esac

# Remove binary
if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
  printf 'Removing binary...\n'
  rm -f "${INSTALL_DIR}/${BINARY_NAME}"
  green "✓ Binary removed"
else
  yellow "Binary not found, skipping"
fi

# Ask about config files
if [[ -d "$CONFIG_DIR" ]]; then
  printf '\n'
  yellow "Configuration directory found: ${CONFIG_DIR}"
  printf 'This contains your host ID and API token.\n'
  printf 'Remove configuration files? [y/N] '
  read -r response

  if [[ "$response" =~ ^[Yy]$ ]]; then
    printf 'Removing configuration...\n'
    rm -rf "$CONFIG_DIR"
    green "✓ Configuration removed"
  else
    yellow "Configuration preserved at ${CONFIG_DIR}"
    printf '  To remove manually later: sudo rm -rf "%s"\n' "$CONFIG_DIR"
  fi
else
  yellow "Configuration directory not found, skipping"
fi

# Remove log file (macOS only)
if [[ "$OS" == "Darwin" && -f "/var/log/mitori-agent.log" ]]; then
  printf 'Removing log file...\n'
  rm -f /var/log/mitori-agent.log
  green "✓ Log file removed"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

green ""
green "✓ Mitori agent uninstalled successfully!"
green ""
printf 'The agent has been removed from your system.\n'

# Check if process is still running
if pgrep -f "$BINARY_NAME" >/dev/null 2>&1; then
  yellow ""
  yellow "Warning: A mitori-agent process is still running."
  yellow "You may need to manually kill it: sudo pkill -f mitori-agent"
fi
