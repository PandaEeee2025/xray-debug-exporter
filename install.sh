# Xray Debug Exporter — install.sh v1.0.1
#!/bin/bash

set -euo pipefail

# ============================================================
# Xray Debug Exporter Installer
# Version: 1.0.1
# ============================================================

VERSION="1.0.1"
PROJECT_NAME="xray-debug-exporter"

INSTALL_DIR="/usr/local/bin"
INSTALL_BIN="${INSTALL_DIR}/xray-debug-exporter.py"

CONFIG_DIR="/etc/xray-debug-exporter"
CONFIG_FILE="${CONFIG_DIR}/config.conf"

SERVICE_DIR="/etc/systemd/system"
SERVICE_FILE="${SERVICE_DIR}/${PROJECT_NAME}.service"

STATE_DIR="/var/lib/xray-debug-exporter"
STATE_FILE="${STATE_DIR}/installed"

EXPORTER_USER="xray-exporter"
EXPORTER_GROUP="xray-exporter"

# GitHub source
GITHUB_RAW="https://raw.githubusercontent.com/PandaEeee2025/xray-debug-exporter/main"

SOURCE_URL="${GITHUB_RAW}/xray-debug-exporter.py"

# Xray
DEFAULT_XRAY_URL="http://127.0.0.1:11111/debug/vars"

# Exporter defaults
DEFAULT_PORT="9101"
DEFAULT_INTERVAL="15"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'


# ============================================================
# Logging
# ============================================================

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

    error "This installer must be run as root."

    echo
    echo "Use:"
    echo "  sudo bash install.sh"

    exit 1

fi


# ============================================================
# Banner
# ============================================================

echo
echo "=============================================="
echo "     Xray Debug Exporter v${VERSION}"
echo "=============================================="
echo


# ============================================================
# Detect Python
# ============================================================

PYTHON_BIN="$(command -v python3 || true)"

if [ -z "$PYTHON_BIN" ]; then

    error "Python 3 was not found."

    exit 1

fi

info "Python: ${PYTHON_BIN}"


# ============================================================
# Detect download tool
# ============================================================

DOWNLOAD_TOOL=""

if command -v curl >/dev/null 2>&1; then

    DOWNLOAD_TOOL="curl"

elif command -v wget >/dev/null 2>&1; then

    DOWNLOAD_TOOL="wget"

else

    error "Neither curl nor wget was found."

    echo
    echo "Install curl or wget and try again."

    exit 1

fi

info "Download tool: ${DOWNLOAD_TOOL}"


# ============================================================
# Download source
# ============================================================

TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT


TEMP_SOURCE="${TEMP_DIR}/xray-debug-exporter.py"


echo
info "Downloading exporter source..."

if [ "$DOWNLOAD_TOOL" = "curl" ]; then

    curl \
        -fsSL \
        --retry 3 \
        --connect-timeout 10 \
        "$SOURCE_URL" \
        -o "$TEMP_SOURCE"

else

    wget \
        -q \
        --tries=3 \
        --timeout=10 \
        "$SOURCE_URL" \
        -O "$TEMP_SOURCE"

fi


if [ ! -s "$TEMP_SOURCE" ]; then

    error "Failed to download exporter source."

    exit 1

fi

info "Exporter source downloaded."


# ============================================================
# Validate downloaded Python source
# ============================================================

info "Validating Python source..."

if ! "$PYTHON_BIN" -m py_compile "$TEMP_SOURCE"; then

    error "Python source validation failed."

    exit 1

fi

info "Python source validation passed."


# ============================================================
# Check Xray /debug/vars
# ============================================================

echo
info "Checking Xray /debug/vars..."

if ! "$PYTHON_BIN" - "$DEFAULT_XRAY_URL" <<'PY'
import json
import sys
import urllib.request

url = sys.argv[1]

try:

    with urllib.request.urlopen(url, timeout=5) as response:

        data = json.loads(
            response.read().decode()
        )

    if not isinstance(data, dict):

        raise ValueError(
            "Xray returned invalid JSON object"
        )

except Exception as exc:

    print(
        f"Xray check failed: {exc}",
        file=sys.stderr
    )

    sys.exit(1)
PY
then

    error "Xray /debug/vars is not reachable."

    echo
    echo "Expected:"
    echo "  ${DEFAULT_XRAY_URL}"

    echo
    echo "Check that Xray /debug/vars is enabled."

    exit 1

fi

info "Xray /debug/vars is reachable."


# ============================================================
# Detect Tailscale IPv4
# ============================================================

TAILSCALE_IP=""

if command -v tailscale >/dev/null 2>&1; then

    TAILSCALE_IP="$(
        tailscale ip -4 2>/dev/null |
        head -n 1 ||
        true
    )"

fi


if [ -n "$TAILSCALE_IP" ]; then

    info "Detected Tailscale IPv4: ${TAILSCALE_IP}"

else

    warn "Tailscale IPv4 was not detected."

fi


# ============================================================
# Select listen address
# ============================================================

echo
echo "Select exporter listen address:"
echo

if [ -n "$TAILSCALE_IP" ]; then

    echo "  1) Tailscale IP (${TAILSCALE_IP}) [recommended]"

fi

echo "  2) 0.0.0.0"
echo "  3) Custom IP"
echo


if [ -n "$TAILSCALE_IP" ]; then

    read -r -p "Select [1]: " LISTEN_CHOICE

    LISTEN_CHOICE="${LISTEN_CHOICE:-1}"

else

    read -r -p "Select [2]: " LISTEN_CHOICE

    LISTEN_CHOICE="${LISTEN_CHOICE:-2}"

fi


case "$LISTEN_CHOICE" in

    1)

        if [ -z "$TAILSCALE_IP" ]; then

            error "Tailscale IP is not available."

            exit 1

        fi

        LISTEN_IP="$TAILSCALE_IP"

        ;;


    2)

        LISTEN_IP="0.0.0.0"

        ;;


    3)

        read -r -p "Enter listen IP: " LISTEN_IP

        if [ -z "$LISTEN_IP" ]; then

            error "Listen IP cannot be empty."

            exit 1

        fi

        ;;


    *)

        error "Invalid selection."

        exit 1

        ;;

esac


# ============================================================
# Port
# ============================================================

echo

read -r \
    -p "Exporter port [${DEFAULT_PORT}]: " \
    LISTEN_PORT

LISTEN_PORT="${LISTEN_PORT:-$DEFAULT_PORT}"


if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]]; then

    error "Invalid port."

    exit 1

fi


if [ "$LISTEN_PORT" -lt 1 ] ||
   [ "$LISTEN_PORT" -gt 65535 ]; then

    error "Port must be between 1 and 65535."

    exit 1

fi


# ============================================================
# Update interval
# ============================================================

echo

read -r \
    -p "Update interval in seconds [${DEFAULT_INTERVAL}]: " \
    UPDATE_INTERVAL

UPDATE_INTERVAL="${UPDATE_INTERVAL:-$DEFAULT_INTERVAL}"


if ! [[ "$UPDATE_INTERVAL" =~ ^[0-9]+$ ]]; then

    error "Invalid update interval."

    exit 1

fi


if [ "$UPDATE_INTERVAL" -lt 1 ]; then

    error "Update interval must be at least 1 second."

    exit 1

fi


# ============================================================
# Installation summary
# ============================================================

echo
echo "=============================================="
echo " Installation configuration"
echo "=============================================="
echo

echo "Version:"
echo "  ${VERSION}"

echo

echo "Xray:"
echo "  ${DEFAULT_XRAY_URL}"

echo

echo "Listen:"
echo "  ${LISTEN_IP}:${LISTEN_PORT}"

echo

echo "Update interval:"
echo "  ${UPDATE_INTERVAL}s"

echo


# ============================================================
# Confirmation
# ============================================================

read -r \
    -p "Continue installation? [Y/n]: " \
    CONFIRM

CONFIRM="${CONFIRM:-Y}"


case "$CONFIRM" in

    Y|y|YES|yes|Yes)
        ;;

    *)

        echo
        echo "Installation cancelled."

        exit 0

        ;;

esac


# ============================================================
# Check port
# ============================================================

if command -v ss >/dev/null 2>&1; then

    if ss -lnt 2>/dev/null |
        grep -Eq \
        "(^|[[:space:]])${LISTEN_IP}:${LISTEN_PORT}[[:space:]]"; then

        warn "Port ${LISTEN_PORT} appears to be in use."

        echo

        ss -lntp 2>/dev/null |
            grep ":${LISTEN_PORT}" ||
            true

        echo

        read -r \
            -p "Continue anyway? [y/N]: " \
            PORT_CONFIRM

        case "$PORT_CONFIRM" in

            Y|y|YES|yes|Yes)
                ;;

            *)

                echo
                echo "Installation cancelled."

                exit 0

                ;;

        esac

    fi

fi


# ============================================================
# Create exporter group
# ============================================================

echo

info "Creating exporter group..."

if getent group "$EXPORTER_GROUP" >/dev/null 2>&1; then

    info "Group ${EXPORTER_GROUP} already exists."

else

    groupadd \
        --system \
        "$EXPORTER_GROUP"

    info "Created group ${EXPORTER_GROUP}."

fi


# ============================================================
# Create exporter user
# ============================================================

info "Creating exporter user..."

if id "$EXPORTER_USER" >/dev/null 2>&1; then

    info "User ${EXPORTER_USER} already exists."

else

    useradd \
        --system \
        --gid "$EXPORTER_GROUP" \
        --no-create-home \
        --shell /usr/sbin/nologin \
        "$EXPORTER_USER"

    info "Created user ${EXPORTER_USER}."

fi


# ============================================================
# Create directories
# ============================================================

info "Creating directories..."

mkdir -p "$CONFIG_DIR"
mkdir -p "$STATE_DIR"

chown root:root "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

chown root:root "$STATE_DIR"
chmod 755 "$STATE_DIR"


# ============================================================
# Install exporter
# ============================================================

info "Installing exporter..."

install \
    -o root \
    -g root \
    -m 755 \
    "$TEMP_SOURCE" \
    "$INSTALL_BIN"


# ============================================================
# Configuration
# ============================================================

if [ -f "$CONFIG_FILE" ]; then

    echo
    warn "Existing configuration detected:"
    echo
    echo "  ${CONFIG_FILE}"
    echo

    read -r \
        -p "Overwrite existing configuration? [y/N]: " \
        OVERWRITE

    case "$OVERWRITE" in

        Y|y|YES|yes|Yes)

            info "Overwriting configuration."

            cat > "$CONFIG_FILE" <<EOF
# Xray Debug Exporter configuration

# Xray debug endpoint
XRAY_URL=${DEFAULT_XRAY_URL}

# Address where Prometheus exporter will listen
LISTEN_IP=${LISTEN_IP}

# Prometheus exporter port
LISTEN_PORT=${LISTEN_PORT}

# How often to update data from Xray
UPDATE_INTERVAL=${UPDATE_INTERVAL}
EOF

            ;;

        *)

            info "Existing configuration will be preserved."

            ;;

    esac

else

    info "Creating configuration..."

    cat > "$CONFIG_FILE" <<EOF
# Xray Debug Exporter configuration

# Xray debug endpoint
XRAY_URL=${DEFAULT_XRAY_URL}

# Address where Prometheus exporter will listen
LISTEN_IP=${LISTEN_IP}

# Prometheus exporter port
LISTEN_PORT=${LISTEN_PORT}

# How often to update data from Xray
UPDATE_INTERVAL=${UPDATE_INTERVAL}
EOF

fi


# ============================================================
# Configuration permissions
# ============================================================

chown \
    "$EXPORTER_USER:$EXPORTER_GROUP" \
    "$CONFIG_FILE"

chmod 640 "$CONFIG_FILE"


# ============================================================
# Create systemd service
# ============================================================

info "Installing systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Debug Vars Prometheus Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}

ExecStart=${PYTHON_BIN} ${INSTALL_BIN}

Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF


chown root:root "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"


# ============================================================
# Installation state
# ============================================================

cat > "$STATE_FILE" <<EOF
PROJECT=${PROJECT_NAME}
VERSION=${VERSION}
USER=${EXPORTER_USER}
GROUP=${EXPORTER_GROUP}
EOF

chmod 644 "$STATE_FILE"


# ============================================================
# Reload systemd
# ============================================================

info "Reloading systemd..."

systemctl daemon-reload


# ============================================================
# Enable service
# ============================================================

info "Enabling service..."

systemctl enable \
    "$PROJECT_NAME.service" \
    >/dev/null


# ============================================================
# Start service
# ============================================================

info "Starting exporter..."

systemctl restart \
    "$PROJECT_NAME.service"


sleep 1


# ============================================================
# Verify service
# ============================================================

if ! systemctl is-active \
    --quiet \
    "$PROJECT_NAME.service"; then

    error "Exporter service failed to start."

    echo
    systemctl status \
        "$PROJECT_NAME.service" \
        --no-pager ||
        true

    echo
    echo "Logs:"

    journalctl \
        -u "$PROJECT_NAME.service" \
        -n 30 \
        --no-pager ||
        true

    exit 1

fi


info "Exporter service is running."


# ============================================================
# Verify metrics
# ============================================================

echo

info "Checking Prometheus metrics endpoint..."

METRICS_URL="http://${LISTEN_IP}:${LISTEN_PORT}/metrics"


if ! "$PYTHON_BIN" - "$METRICS_URL" <<'PY'
import sys
import urllib.request

url = sys.argv[1]

try:

    with urllib.request.urlopen(
        url,
        timeout=5
    ) as response:

        body = response.read().decode()

    if "xray_debug_up" not in body:

        raise RuntimeError(
            "xray_debug_up metric was not found"
        )

except Exception as exc:

    print(
        f"Metrics check failed: {exc}",
        file=sys.stderr
    )

    sys.exit(1)
PY
then

    error "Prometheus endpoint is not working."

    echo
    echo "Service logs:"

    journalctl \
        -u "$PROJECT_NAME.service" \
        -n 30 \
        --no-pager ||
        true

    exit 1

fi


info "Prometheus endpoint is working."


# ============================================================
# Final information
# ============================================================

echo
echo "=============================================="
echo " Installation completed successfully!"
echo "=============================================="
echo

echo "Version:"
echo "  ${VERSION}"

echo

echo "Exporter:"
echo "  ${INSTALL_BIN}"

echo

echo "Configuration:"
echo "  ${CONFIG_FILE}"

echo

echo "Metrics:"
echo "  ${METRICS_URL}"

echo

echo "Service:"
echo "  systemctl status ${PROJECT_NAME}"

echo

echo "Logs:"
echo "  journalctl -u ${PROJECT_NAME} -f"

echo

echo "User:"
echo "  ${EXPORTER_USER}"

echo
