#!/usr/bin/env python3

import json
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread, Lock


# ============================================================
# Configuration
# ============================================================

CONFIG_FILE = "/etc/xray-debug-exporter/config.conf"

XRAY_URL = "http://127.0.0.1:11111/debug/vars"
LISTEN_IP = "127.0.0.1"
LISTEN_PORT = 9101
UPDATE_INTERVAL = 15


# ============================================================
# Runtime state
# ============================================================

data = {}
data_lock = Lock()

last_update = 0
xray_available = False


# ============================================================
# Configuration loader
# ============================================================

def load_config():

    global XRAY_URL
    global LISTEN_IP
    global LISTEN_PORT
    global UPDATE_INTERVAL

    config = {}

    try:

        with open(CONFIG_FILE, "r") as f:

            for line in f:

                line = line.strip()

                # Empty line
                if not line:
                    continue

                # Comment
                if line.startswith("#"):
                    continue

                # Invalid line
                if "=" not in line:
                    continue

                key, value = line.split("=", 1)

                key = key.strip()

                value = (
                    value
                    .strip()
                    .strip('"')
                    .strip("'")
                )

                config[key] = value

    except FileNotFoundError:

        print(
            f"Config file not found: {CONFIG_FILE}. "
            f"Using defaults.",
            flush=True
        )

        return

    # Xray URL

    XRAY_URL = config.get(
        "XRAY_URL",
        XRAY_URL
    )

    # Listen IP

    LISTEN_IP = config.get(
        "LISTEN_IP",
        LISTEN_IP
    )

    # Listen port

    try:

        LISTEN_PORT = int(
            config.get(
                "LISTEN_PORT",
                LISTEN_PORT
            )
        )

    except ValueError:

        print(
            f"Invalid LISTEN_PORT in config. "
            f"Using {LISTEN_PORT}",
            flush=True
        )

    # Update interval

    try:

        UPDATE_INTERVAL = int(
            config.get(
                "UPDATE_INTERVAL",
                UPDATE_INTERVAL
            )
        )

    except ValueError:

        print(
            f"Invalid UPDATE_INTERVAL in config. "
            f"Using {UPDATE_INTERVAL}",
            flush=True
        )


# Load configuration before starting exporter

load_config()


# ============================================================
# Xray API
# ============================================================

def fetch_xray():

    with urllib.request.urlopen(
        XRAY_URL,
        timeout=5
    ) as response:

        raw_data = response.read().decode()

        return json.loads(raw_data)


# ============================================================
# Prometheus label escaping
# ============================================================

def escape_label(value):

    return (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


# ============================================================
# Generate Prometheus metrics
# ============================================================

def generate_metrics():

    with data_lock:

        current_data = data.copy()

    lines = []

    stats = current_data.get(
        "stats",
        {}
    )


    # ========================================================
    # Exporter / Xray status
    # ========================================================

    lines.append(
        "# HELP xray_debug_up "
        "Whether Xray /debug/vars is reachable"
    )

    lines.append(
        "# TYPE xray_debug_up gauge"
    )

    lines.append(
        f"xray_debug_up "
        f"{1 if xray_available else 0}"
    )


    # Last successful update

    lines.append(
        "# HELP xray_debug_last_update_timestamp "
        "Unix timestamp of last successful Xray update"
    )

    lines.append(
        "# TYPE xray_debug_last_update_timestamp gauge"
    )

    lines.append(
        f"xray_debug_last_update_timestamp "
        f"{last_update}"
    )


    # ========================================================
    # Inbound
    # ========================================================

    inbound = stats.get(
        "inbound",
        {}
    )


    # Uplink

    lines.append(
        "# HELP xray_inbound_uplink_bytes "
        "Total uplink bytes for Xray inbound"
    )

    lines.append(
        "# TYPE xray_inbound_uplink_bytes counter"
    )

    for name, values in inbound.items():

        label = escape_label(name)

        lines.append(
            f'xray_inbound_uplink_bytes'
            f'{{inbound="{label}"}} '
            f'{values.get("uplink", 0)}'
        )


    # Downlink

    lines.append(
        "# HELP xray_inbound_downlink_bytes "
        "Total downlink bytes for Xray inbound"
    )

    lines.append(
        "# TYPE xray_inbound_downlink_bytes counter"
    )

    for name, values in inbound.items():

        label = escape_label(name)

        lines.append(
            f'xray_inbound_downlink_bytes'
            f'{{inbound="{label}"}} '
            f'{values.get("downlink", 0)}'
        )


    # ========================================================
    # Outbound
    # ========================================================

    outbound = stats.get(
        "outbound",
        {}
    )


    # Uplink

    lines.append(
        "# HELP xray_outbound_uplink_bytes "
        "Total uplink bytes for Xray outbound"
    )

    lines.append(
        "# TYPE xray_outbound_uplink_bytes counter"
    )

    for name, values in outbound.items():

        label = escape_label(name)

        lines.append(
            f'xray_outbound_uplink_bytes'
            f'{{outbound="{label}"}} '
            f'{values.get("uplink", 0)}'
        )


    # Downlink

    lines.append(
        "# HELP xray_outbound_downlink_bytes "
        "Total downlink bytes for Xray outbound"
    )

    lines.append(
        "# TYPE xray_outbound_downlink_bytes counter"
    )

    for name, values in outbound.items():

        label = escape_label(name)

        lines.append(
            f'xray_outbound_downlink_bytes'
            f'{{outbound="{label}"}} '
            f'{values.get("downlink", 0)}'
        )


    # ========================================================
    # Users
    # ========================================================

    users = stats.get(
        "user",
        {}
    )


    # Uplink

    lines.append(
        "# HELP xray_user_uplink_bytes "
        "Total uplink bytes for Xray user"
    )

    lines.append(
        "# TYPE xray_user_uplink_bytes counter"
    )

    for name, values in users.items():

        label = escape_label(name)

        lines.append(
            f'xray_user_uplink_bytes'
            f'{{user="{label}"}} '
            f'{values.get("uplink", 0)}'
        )


    # Downlink

    lines.append(
        "# HELP xray_user_downlink_bytes "
        "Total downlink bytes for Xray user"
    )

    lines.append(
        "# TYPE xray_user_downlink_bytes counter"
    )

    for name, values in users.items():

        label = escape_label(name)

        lines.append(
            f'xray_user_downlink_bytes'
            f'{{user="{label}"}} '
            f'{values.get("downlink", 0)}'
        )


    return "\n".join(lines) + "\n"


# ============================================================
# HTTP server
# ============================================================

class MetricsHandler(BaseHTTPRequestHandler):

    def do_GET(self):

        # Only /metrics is available

        if self.path != "/metrics":

            self.send_response(404)

            self.end_headers()

            return


        try:

            metrics = generate_metrics()

            encoded = metrics.encode()


            self.send_response(200)


            self.send_header(
                "Content-Type",
                "text/plain; version=0.0.4"
            )


            self.send_header(
                "Content-Length",
                str(len(encoded))
            )


            self.end_headers()


            self.wfile.write(encoded)


        except Exception as e:

            self.send_response(500)

            self.end_headers()

            self.wfile.write(
                str(e).encode()
            )


    # Disable standard HTTP request logging

    def log_message(
        self,
        format,
        *args
    ):

        return


# ============================================================
# Xray update loop
# ============================================================

def update_loop():

    global data
    global last_update
    global xray_available


    while True:

        try:

            new_data = fetch_xray()


            with data_lock:

                data = new_data


            last_update = int(
                time.time()
            )

            xray_available = True


        except Exception as e:

            xray_available = False


            print(
                f"Error reading Xray: {e}",
                flush=True
            )


        time.sleep(
            UPDATE_INTERVAL
        )


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":


    # --------------------------------------------------------
    # Initial Xray connection
    # --------------------------------------------------------

    try:

        new_data = fetch_xray()


        with data_lock:

            data = new_data


        last_update = int(
            time.time()
        )

        xray_available = True


        print(
            "Successfully connected to "
            "Xray /debug/vars",
            flush=True
        )


    except Exception as e:

        print(
            f"Initial Xray connection failed: {e}",
            flush=True
        )


    # --------------------------------------------------------
    # Start background updater
    # --------------------------------------------------------

    updater = Thread(
        target=update_loop,
        daemon=True
    )

    updater.start()


    # --------------------------------------------------------
    # Start HTTP server
    # --------------------------------------------------------

    server = HTTPServer(
        (
            LISTEN_IP,
            LISTEN_PORT
        ),
        MetricsHandler
    )


    print(
        f"Xray Debug Exporter listening on "
        f"{LISTEN_IP}:{LISTEN_PORT}",
        flush=True
    )


    server.serve_forever()
