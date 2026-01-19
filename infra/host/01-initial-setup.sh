#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - Initial Host Setup
# ============================================================================
# This script performs initial hardening and package installation on the
# Contabo VDS host. Run as root after fresh OS install.
#
# Security rationale:
# - Update system to patch known vulnerabilities
# - Install only required packages (minimal attack surface)
# - Prepare for WireGuard VPN (sole entry point)
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "VTCS Cyber Range - Initial Host Setup"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# System update
echo "[1/5] Updating system packages..."
apt update && apt upgrade -y

# Install essential packages
echo "[2/5] Installing essential packages..."
apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    tmux \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    ufw \
    wireguard \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    bridge-utils \
    cockpit \
    cockpit-machines

# Enable automatic security updates
echo "[3/5] Configuring automatic security updates..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Configure fail2ban for SSH protection (until VPN-only access is enforced)
echo "[4/5] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Enable and start libvirt
echo "[5/5] Enabling virtualization services..."
systemctl enable libvirtd
systemctl start libvirtd

# Add current user to libvirt group (if not root)
# usermod -aG libvirt $SUDO_USER 2>/dev/null || true

echo ""
echo "=========================================="
echo "Initial setup complete!"
echo "=========================================="
echo "Next steps:"
echo "  1. Run 02-wireguard-setup.sh to configure VPN"
echo "  2. Run 03-firewall-setup.sh to lock down access"
echo "  3. Run 04-cockpit-hardening.sh to secure Cockpit"
echo ""
