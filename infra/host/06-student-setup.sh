#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Student User Setup on VDS
# ============================================================================
# Creates student users on VDS with ForceCommand to their containers.
# Run this on VDS AFTER:
#   1. Lab VM is running with containers
#   2. /etc/cyberlab/keys/labvm_key exists
#   3. labvm SSH alias is configured
#
# This creates: red1, red2, red3, blue1, blue2, blue3
# Each user SSH's to VDS → ForceCommand → student-shell.sh → container
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "VTCS Cyber Range - Student User Setup"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Check prerequisites
if ! grep -q "Host labvm" /etc/ssh/ssh_config.d/labvm.conf 2>/dev/null; then
    echo "ERROR: labvm SSH alias not configured."
    echo "       Ensure /etc/ssh/ssh_config.d/labvm.conf exists."
    exit 1
fi

# Create student users
echo "[1/3] Creating student users..."

STUDENTS=("red1" "red2" "red3" "blue1" "blue2" "blue3")

for student in "${STUDENTS[@]}"; do
    if ! id "$student" &>/dev/null; then
        useradd -m -s /bin/bash "$student"
        echo "  Created user '$student'"
    else
        echo "  User '$student' already exists"
    fi
    
    # Create .ssh directory
    mkdir -p "/home/$student/.ssh"
    chmod 700 "/home/$student/.ssh"
    chown "$student:$student" "/home/$student/.ssh"
done

# Configure sshd for student ForceCommand
echo "[2/3] Configuring sshd for students..."

# Create drop-in config for students
cat > /etc/ssh/sshd_config.d/students.conf << 'EOF'
# ============================================================================
# VTCS Cyber Range - Student SSH Configuration
# ============================================================================
# Students SSH to VDS and are automatically connected to their container.
# The -tt flag forces PTY allocation for Windows PowerShell compatibility.
# ============================================================================

# Red Team
Match User red1
    ForceCommand ssh -tt labvm docker exec -it red1 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no

Match User red2
    ForceCommand ssh -tt labvm docker exec -it red2 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no

Match User red3
    ForceCommand ssh -tt labvm docker exec -it red3 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no

# Blue Team
Match User blue1
    ForceCommand ssh -tt labvm docker exec -it blue1 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no

Match User blue2
    ForceCommand ssh -tt labvm docker exec -it blue2 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no

Match User blue3
    ForceCommand ssh -tt labvm docker exec -it blue3 bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
EOF

# Test sshd config
echo "[3/3] Testing sshd configuration..."
if sshd -t; then
    echo "  sshd config OK, reloading..."
    systemctl reload sshd
else
    echo "ERROR: sshd config test failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "Student user setup complete!"
echo "=========================================="
echo ""
echo "Students created: ${STUDENTS[*]}"
echo ""
echo "NEXT STEPS:"
echo "1. Generate SSH keys for each student:"
echo "   ssh-keygen -t ed25519 -f red1.key -N '' -C 'red1@vtcs'"
echo ""
echo "2. Add public keys to authorized_keys:"
echo "   cat red1.key.pub >> /home/red1/.ssh/authorized_keys"
echo "   chown red1:red1 /home/red1/.ssh/authorized_keys"
echo "   chmod 600 /home/red1/.ssh/authorized_keys"
echo ""
echo "3. Distribute keys via user-packages"
echo ""
echo "Students connect with: ssh -i <key> <user>@10.200.0.1"
echo ""
