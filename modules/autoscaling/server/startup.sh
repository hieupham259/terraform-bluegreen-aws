#!/bin/bash
set -e

# 1) Render the page served by the web server.
mkdir -p /var/www
tee /var/www/index.html > /dev/null <<EOF
${HTML}
EOF

# 2) Define a systemd service so the web server is managed: it runs in the
#    background, restarts on failure, survives reboots, and does NOT block
#    cloud-init (unlike running python in the foreground from user-data).
tee /etc/systemd/system/webserver.service > /dev/null <<'UNIT'
[Unit]
Description=Simple Python web server
After=network.target

[Service]
WorkingDirectory=/var/www
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

# 3) Start it now and enable it to start on every boot.
systemctl daemon-reload
systemctl enable --now webserver
