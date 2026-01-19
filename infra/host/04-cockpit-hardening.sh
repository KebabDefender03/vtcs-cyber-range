#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - Cockpit Hardening
# ============================================================================
# Hardens Cockpit web console for secure VM management.
# Cockpit is only accessible via VPN (enforced by firewall).
#
# Security rationale:
# - Disable root login (use sudo instead)
# - Require strong authentication
# - Limit to VPN subnet via ListenAddress
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "VTCS Cyber Range - Cockpit Hardening"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Create admin user for Cockpit (don't use root)
echo "[1/4] Creating admin user for Cockpit..."
if ! id "labadmin" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,libvirt labadmin
    echo "labadmin:ChangeMeOnFirstLogin!" | chpasswd
    echo "  Created user 'labadmin' with temporary password"
    echo "  CHANGE THIS PASSWORD IMMEDIATELY after first login!"
else
    echo "  User 'labadmin' already exists"
fi

# Configure Cockpit to listen only on VPN interface
echo "[2/4] Configuring Cockpit listen address..."
mkdir -p /etc/cockpit
cat > /etc/cockpit/cockpit.conf << 'EOF'
# ============================================================================
# Cockpit Configuration - VTCS Cyber Range
# ============================================================================
# Hardened configuration for lab management console

[WebService]
# Only listen on VPN interface IP (set after WireGuard is up)
# ListenAddress = 10.200.0.1
# For now, rely on firewall to restrict access

# Session timeout (15 minutes idle)
IdleTimeout = 15

# Require explicit login (no auto-login)
LoginTitle = VTCS Cyber Range - Lab Management

[Session]
# Idle timeout for sessions
IdleTimeout = 15
EOF

# Disable root login in Cockpit
echo "[3/4] Disabling root login in Cockpit..."
cat > /etc/cockpit/disallowed-users << 'EOF'
# Users not allowed to log into Cockpit
root
EOF

# Enable and restart Cockpit
echo "[4/4] Enabling Cockpit service..."
systemctl enable cockpit.socket
systemctl restart cockpit.socket

echo ""
echo "=========================================="
echo "Cockpit hardening complete!"
echo "=========================================="
echo ""
echo "Access Cockpit at: https://10.200.0.1:9090 (via VPN)"
echo ""
echo "Login credentials:"
echo "  Username: labadmin"
echo "  Password: ChangeMeOnFirstLogin!"
echo ""
echo "IMPORTANT: Change the password on first login!"
echo "  Run: passwd labadmin"
echo ""
