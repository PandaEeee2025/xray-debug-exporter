# Xray Debug Exporter

Lightweight Prometheus exporter for Xray using the built-in `/debug/vars` endpoint.

The exporter periodically reads runtime statistics from Xray and exposes them in Prometheus-compatible format.

No modification of Xray configuration is required beyond enabling the `/debug/vars` endpoint.

---

## Features

- Reads Xray runtime statistics from `/debug/vars`
- Exposes metrics for Prometheus
- Tracks inbound traffic
- Tracks outbound traffic
- Tracks traffic per Xray user
- Automatic Tailscale IPv4 detection
- Manual listen address selection
- Configurable exporter port
- Configurable update interval
- systemd service
- Dedicated unprivileged `xray-exporter` user
- systemd security hardening
- Automatic installation
- Automatic uninstallation
- No external Python packages required

---

## Install

curl -fsSL https://raw.githubusercontent.com/PandaEeee2025/xray-debug-exporter/main/install.sh | sudo bash

## Architecture

```text
                         Xray
                          │
                          │ /debug/vars
                          │
                          ▼
                ┌─────────────────────┐
                │ Xray Debug Exporter │
                │                     │
                │ Python 3            │
                │ :9101/metrics      │
                └──────────┬──────────┘
                           │
                           │ Prometheus scrape
                           ▼
                  ┌─────────────────┐
                  │    Prometheus   │
                  └────────┬────────┘
                           │
                           ▼
                     ┌───────────┐
                     │  Grafana  │
                     └───────────┘

