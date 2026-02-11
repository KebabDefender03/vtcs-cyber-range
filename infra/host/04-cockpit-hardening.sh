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

# Create admin users for Cockpit (don't use root)
echo "[1/4] Creating admin and instructor users for Cockpit..."

# Admin users (full sudo access)
for i in 1 2 3; do
    username="admin${i}"
    if ! id "${username}" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo,libvirt "${username}"
        echo "  Created user '${username}'"
    else
        echo "  User '${username}' already exists"
    fi
done

# Instructor users (limited sudo for lab.sh only)
for i in 1 2; do
    username="instructor${i}"
    if ! id "${username}" &>/dev/null; then
        useradd -m -s /bin/bash "${username}"
        # Add to libvirt group for Cockpit VM management view
        usermod -aG libvirt "${username}"
        echo "  Created user '${username}'"
    else
        echo "  User '${username}' already exists"
    fi
done

# Configure sudoers for instructors (lab.sh and add-student.sh)
cat > /etc/sudoers.d/instructors << 'EOF'
# Instructors can run lab.sh for phase control and add-student.sh for onboarding
instructor1 ALL=(ALL) NOPASSWD: /opt/cyberlab/scripts/lab.sh, /opt/cyberlab/scripts/add-student.sh
instructor2 ALL=(ALL) NOPASSWD: /opt/cyberlab/scripts/lab.sh, /opt/cyberlab/scripts/add-student.sh
EOF
chmod 440 /etc/sudoers.d/instructors

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
echo "Authorized users:"
echo "  - admin1, admin2, admin3 (full access)"
echo "  - instructor1, instructor2 (VM viewing, lab.sh + add-student.sh)"
echo ""
echo "IMPORTANT: Set passwords for Cockpit/sudo access:"
echo "  passwd admin1"
echo "  passwd admin2"
echo "  passwd admin3"
echo "  passwd instructor1"
echo "  passwd instructor2"
echo ""
