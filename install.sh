#!/bin/bash
set -e

# Define color outputs for premium CLI experience
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}          Kinnector EDR Agent Bootstrapper          ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root. Please run with sudo.${NC}"
    exit 1
fi

# 2. Verify OS Compatibility (Debian/Ubuntu only)
if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}Error: Kinnector EDR Agent currently only supports Debian/Ubuntu derivatives.${NC}"
    exit 1
fi

# 3. Verify CPU Architecture (AMD64 only)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo -e "${RED}Error: Kinnector EDR Agent currently only supports amd64 (x86_64) architecture.${NC}"
    exit 1
fi

# 4. Resolve dependencies
echo -e "${BLUE}[*] Resolving dependencies...${NC}"
apt-get update -y
apt-get install -y libc6 libbpf1 || apt-get install -y libc6 libbpf0 || true

# 5. Locate and install package
INSTALL_DIR="/home/user/Documents/kinnector/kinnector-installer"
LOCAL_DEB="${INSTALL_DIR}/kinnector-agent_1.0.0_amd64.deb"

if [ -f "$LOCAL_DEB" ]; then
    echo -e "${GREEN}[*] Found local package. Installing ${LOCAL_DEB}...${NC}"
    dpkg -i "$LOCAL_DEB"
else
    # Fallback to remote download or compiling if not found (simulated for installer script)
    echo -e "${YELLOW}[!] Local Debian package not found at ${LOCAL_DEB}.${NC}"
    echo -e "${BLUE}[*] Attempting to rebuild package using build_deb.sh...${NC}"
    if [ -f "${INSTALL_DIR}/build_deb.sh" ]; then
        bash "${INSTALL_DIR}/build_deb.sh"
        dpkg -i "$LOCAL_DEB"
    else
        echo -e "${RED}Error: Could not find build_deb.sh to compile package.${NC}"
        exit 1
    fi
fi

# 6. Verify Service Status
echo -e "\n${BLUE}[*] Verifying EDR Agent Daemon status...${NC}"
if systemctl is-active --quiet kinnector.service; then
    echo -e "${GREEN}Success: kinnector.service is active and running!${NC}"
else
    echo -e "${YELLOW}Warning: kinnector.service is installed but not active. Starting now...${NC}"
    systemctl start kinnector.service || true
fi

# 7. Check BPF LSM Status
echo -e "\n${BLUE}[*] Checking kernel security parameters...${NC}"
LSM_ACTIVE=$(cat /sys/kernel/security/lsm 2>/dev/null || true)
if [[ "$LSM_ACTIVE" == *"bpf"* ]]; then
    echo -e "${GREEN}LSM Mode: Enabled (Kernel enforced). Maximum EDR security protection is active.${NC}"
else
    echo -e "${YELLOW}==================================================================${NC}"
    echo -e "${YELLOW}WARNING: BPF LSM IS DISABLED ON THIS SYSTEM!${NC}"
    echo -e "${YELLOW}The agent is running in USER-MODE fallback detection/enforcement.${NC}"
    echo -e "${YELLOW}Running in user-mode is prone to race conditions and timing bugs.${NC}"
    echo -e "${YELLOW}To enable BPF LSM and secure this host, run:${NC}"
    echo -e "${GREEN}  sudo antitheft-cli lsm-enable${NC}"
    echo -e "${YELLOW}==================================================================${NC}"
fi

echo -e "\n${GREEN}=== Kinnector EDR Bootstrap Installation Completed! ===${NC}"
