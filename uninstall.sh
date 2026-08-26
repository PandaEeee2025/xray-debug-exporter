#!/bin/bash

set -e

PROJECT_NAME="xray-debug-exporter"

INSTALL_BIN="/usr/local/bin/xray-debug-exporter.py"

CONFIG_DIR="/etc/xray-debug-exporter"
SERVICE_FILE="/etc/systemd/system/xray-debug-exporter.service"

STATE_DIR="/var/lib/xray-debug-exporter"
STATE_FILE="${STATE_DIR}/installed"

EXPORTER_USER="xray-exporter"
EXPORTER_GROUP="xray-exporter"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'


info() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


# ============================================================
# Root check
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    error "This uninstaller must be run as root."
    echo "Use: sudo ./uninstall.sh"
    exit 1
fi


echo
echo "=============================================="
echo "     Xray Debug Exporter Uninstaller"
echo "=============================================="
echo


# ============================================================
# Check installation
# ============================================================

if [ ! -f "$STATE_FILE" ] &&
   [ ! -f "$SERVICE_FILE" ] &&
   [ ! -f "$INSTALL_BIN" ]; then

    warn "Xray Debug Exporter does not appear to be installed."

    exit 0

fi


echo "The following components will be removed:"
echo
echo "  Service:"
echo "    $SERVICE_FILE"
echo
echo "  Exporter:"
echo "    $INSTALL_BIN"
echo
echo "  Configuration:"
echo "    $CONFIG_DIR"
echo
echo "  State:"
echo "    $STATE_DIR"
echo
echo "  Service user:"
echo "    $EXPORTER_USER"
echo
warn "Xray, Tailscale and Prometheus will NOT be modified."
echo


read -r -p "Continue uninstall? [y/N]: " CONFIRM


case "$CONFIRM" in
    Y|y|YES|yes|Yes)
        ;;
    *)
        echo
        echo "Uninstallation cancelled."
        exit 0
        ;;
esac


# ============================================================
# Stop service
# ============================================================

if systemctl list-unit-files 2>/dev/null |
    grep -q "^${PROJECT_NAME}.service"; then

    info "Stopping service..."

    systemctl stop "$PROJECT_NAME.service" || true

    info "Disabling service..."

    systemctl disable "$PROJECT_NAME.service" \
        >/dev/null 2>&1 || true

fi


# ============================================================
# Remove systemd service
# ============================================================

if [ -f "$SERVICE_FILE" ]; then

    info "Removing systemd service..."

    rm -f "$SERVICE_FILE"

fi


info "Reloading systemd..."

systemctl daemon-reload


# ============================================================
# Remove exporter
# ============================================================

if [ -f "$INSTALL_BIN" ]; then

    info "Removing exporter..."

    rm -f "$INSTALL_BIN"

fi


# ============================================================
# Remove configuration
# ============================================================

if [ -d "$CONFIG_DIR" ]; then

    info "Removing configuration..."

    rm -rf "$CONFIG_DIR"

fi


# ============================================================
# Remove state
# ============================================================

if [ -d "$STATE_DIR" ]; then

    info "Removing state directory..."

    rm -rf "$STATE_DIR"

fi


# ============================================================
# Remove service user
# ============================================================

if id "$EXPORTER_USER" >/dev/null 2>&1; then

    info "Removing service user..."

    userdel "$EXPORTER_USER"

fi


# ============================================================
# Remove service group
# ============================================================

if getent group "$EXPORTER_GROUP" >/dev/null 2>&1; then

    info "Removing service group..."

    groupdel "$EXPORTER_GROUP" \
        >/dev/null 2>&1 || true

fi


# ============================================================
# Final check
# ============================================================

echo

REMAINING=0


if [ -f "$SERVICE_FILE" ]; then
    REMAINING=1
fi

if [ -f "$INSTALL_BIN" ]; then
    REMAINING=1
fi

if [ -d "$CONFIG_DIR" ]; then
    REMAINING=1
fi

if [ -d "$STATE_DIR" ]; then
    REMAINING=1
fi

if id "$EXPORTER_USER" >/dev/null 2>&1; then
    REMAINING=1
fi


if [ "$REMAINING" -eq 0 ]; then

    echo
    echo "=============================================="
    echo " Uninstallation completed successfully!"
    echo "=============================================="
    echo

else

    error "Some components could not be removed."

    exit 1

fi
