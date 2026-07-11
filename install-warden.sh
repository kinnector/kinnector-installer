#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}          Kinnector Warden Installer & Service      ${NC}"
echo -e "${BLUE}====================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root. Run with sudo.${NC}"
    exit 1
fi

# 1. Setup Directories
echo -e "${BLUE}[*] Setting up directories...${NC}"
mkdir -p /var/run/kinnector
mkdir -p /var/log/kinnector
mkdir -p /etc/kinnector
mkdir -p /var/lib/kinnector/quarantine

chmod 777 /var/run/kinnector # Allow web servers to connect to warden.sock
chmod 755 /var/log/kinnector
chmod 700 /var/lib/kinnector/quarantine

# 2. Copy compiled binary
echo -e "${BLUE}[*] Installing wardend binary...${NC}"
cp /home/user/Documents/kinnector/warden/target/release/warden /usr/local/bin/wardend
chmod 755 /usr/local/bin/wardend

# 3. Create default notifications.json if not exists
if [ ! -f /etc/kinnector/notifications.json ]; then
    echo -e "${BLUE}[*] Creating default notification configurations...${NC}"
    cat << 'EOF' > /etc/kinnector/notifications.json
{
  "notifications": {
    "slack": {
      "enabled": false,
      "webhook_url": ""
    },
    "discord": {
      "enabled": false,
      "webhook_url": ""
    },
    "telegram": {
      "enabled": false,
      "bot_token": "",
      "chat_id": ""
    },
    "generic_webhook": {
      "enabled": false,
      "endpoint": "",
      "headers": {}
    }
  }
}
EOF
    chmod 644 /etc/kinnector/notifications.json
fi

# 4. Create default vulnerability osv.json if not exists
if [ ! -f /etc/kinnector/osv.json ]; then
    echo -e "${BLUE}[*] Creating default OSV dependency vulnerability cache...${NC}"
    cat << 'EOF' > /etc/kinnector/osv.json
[
  {
    "id": "GHSA-c752-h682-g9c6",
    "package": "axios",
    "ecosystem": "npm",
    "vulnerable_version": "0.21.1",
    "patched_version": "0.21.2",
    "severity": "HIGH"
  },
  {
    "id": "CVE-2023-30861",
    "package": "flask",
    "ecosystem": "pip",
    "vulnerable_version": "2.2.0",
    "patched_version": "2.2.5",
    "severity": "HIGH"
  }
]
EOF
    chmod 644 /etc/kinnector/osv.json
fi

# 5. Setup Systemd Service
echo -e "${BLUE}[*] Setting up Systemd service...${NC}"
cat << 'EOF' > /lib/systemd/system/warden.service
[Unit]
Description=Kinnector Warden Server EDR Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wardend --web-root /var/www/html
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart service
systemctl daemon-reload
systemctl enable warden.service
systemctl restart warden.service || true

echo -e "\n${GREEN}=== Kinnector Warden Server EDR Daemon Installed & Started! ===${NC}"
exit 0
