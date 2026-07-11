#!/bin/bash
set -e

echo "=== Kinnector Debian Packaging Builder ==="

# Define paths
WORKSPACE_DIR="/home/user/Documents/kinnector"
BUILD_ROOT="${WORKSPACE_DIR}/kinnector-installer/pkg_build"

# 1. Compile all components in Release mode
echo "[1/4] Compiling components in release mode..."

# Build Core shared library and BPF program
echo "  - Compiling kinnector-core..."
cd "${WORKSPACE_DIR}/kinnector-core"
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Build Agent daemon
echo "  - Compiling kinnector-agent..."
cd "${WORKSPACE_DIR}/kinnector-agent"
cargo build --release

# Build CLI utility
echo "  - Compiling antitheft-cli..."
cd "${WORKSPACE_DIR}/antitheft-cli"
cargo build --release

# Build Warden helper
echo "  - Compiling warden..."
cd "${WORKSPACE_DIR}/warden"
cargo build --release

# Re-generate Config rules.db
echo "  - Generating rules.db..."
cd "${WORKSPACE_DIR}/kinnector-config"
cargo run --release --bin compile_policy "../kinnector-protect-community/policies/" "rules.db"

# 2. Recreate build directory structure inside the workspace
echo "[2/4] Setting up Debian package filesystem layout..."
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}/DEBIAN"
mkdir -p "${BUILD_ROOT}/usr/bin"
mkdir -p "${BUILD_ROOT}/usr/lib/kinnector"
mkdir -p "${BUILD_ROOT}/etc/kinnector"
mkdir -p "${BUILD_ROOT}/lib/systemd/system"

# 3. Copy binaries and assets to layout
echo "[3/4] Copying files into packaging directories..."
cp "${WORKSPACE_DIR}/kinnector-agent/target/release/kinnect-agent" "${BUILD_ROOT}/usr/bin/"
cp "${WORKSPACE_DIR}/antitheft-cli/target/release/antitheft-cli" "${BUILD_ROOT}/usr/bin/"
cp "${WORKSPACE_DIR}/warden/target/release/warden" "${BUILD_ROOT}/usr/bin/"
cp "${WORKSPACE_DIR}/kinnector-core/build/lib/libkinnector-core.so" "${BUILD_ROOT}/usr/lib/"
cp "${WORKSPACE_DIR}/kinnector-core/build/kinnector.bpf.o" "${BUILD_ROOT}/usr/lib/kinnector/"
cp "${WORKSPACE_DIR}/kinnector-config/rules.db" "${BUILD_ROOT}/etc/kinnector/"

# 4. Generate systemd service file
cat << 'EOF' > "${BUILD_ROOT}/lib/systemd/system/kinnector.service"
[Unit]
Description=Kinnector EDR Agent Daemon
After=network.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/usr/lib
ExecStart=/usr/bin/kinnect-agent
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# 5. Generate Debian control and maintainer scripts
cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/control"
Package: kinnector-agent
Version: 1.0.0
Section: admin
Priority: optional
Architecture: amd64
Depends: libc6, libbpf1 | libbpf0
Maintainer: Kinnector Team <admin@kinnector.com>
Description: Kinnector EDR Agent and Core Telemetry Engine
 Kinnector is a lightweight, high-performance endpoint detection and response (EDR) agent
 utilizing eBPF LSM and fanotify to actively monitor and prevent threats in real time.
EOF

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/postinst"
#!/bin/sh
set -e

# Create standard directories
mkdir -p /var/run/kinnector
mkdir -p /var/log/kinnector

# Restrict permissions
chmod 700 /var/run/kinnector
chmod 755 /var/log/kinnector

# Create kinnector group if it doesn't exist
groupadd -f kinnector

# Configure setuid permissions for the warden helper
chown root:kinnector /usr/bin/warden || true
chmod 4750 /usr/bin/warden || true

# Reload systemd and start service
systemctl daemon-reload
systemctl enable kinnector.service
systemctl restart kinnector.service || true

echo "Kinnector EDR Agent installed and started successfully!"
exit 0
EOF

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/prerm"
#!/bin/sh
set -e

# Stop and disable service
systemctl stop kinnector.service || true
systemctl disable kinnector.service || true

# Clean up socket
rm -f /var/run/kinnector/telemetry.sock
rm -f /var/run/kinnector/control.sock

echo "Kinnector EDR Agent stopped and prepared for removal."
exit 0
EOF

# Set permissions for packaging scripts
chmod 755 "${BUILD_ROOT}/DEBIAN/postinst"
chmod 755 "${BUILD_ROOT}/DEBIAN/prerm"

# 6. Build the Debian package
echo "[4/4] Packing debian archive..."
cd "${WORKSPACE_DIR}/kinnector-installer"
dpkg-deb --build pkg_build kinnector-agent_1.0.0_amd64.deb

# Clean up temporary build root
rm -rf "${BUILD_ROOT}"

echo "=== Package Build Completed! ==="
echo "Package located at: ${WORKSPACE_DIR}/kinnector-installer/kinnector-agent_1.0.0_amd64.deb"
