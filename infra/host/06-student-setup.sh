#!/bin/bash
# ============================================================================
# VTCS Cyber Range - SSH & Student Setup on VDS
# ============================================================================
# Configures SSH access to Lab VM for admins/instructors, then creates
# student users with ForceCommand to their containers.
#
# Run this on VDS AFTER:
#   1. Lab VM is running and bootstrapped
#   2. /root/.ssh/portainer_labvm key is authorized on labvm
#
# This script:
#   - Creates labvm SSH config with per-user keys
#   - Creates student users: red1, red2, red3, blue1, blue2, blue3
#   - Configures ForceCommand for container access
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "VTCS Cyber Range - SSH & Student Setup"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Configuration
LABVM_IP=$(virsh domifaddr labvm 2>/dev/null | grep -oP '192\.168\.122\.\d+' | head -1)
ROOT_KEY="/root/.ssh/portainer_labvm"
KEYS_DIR="/etc/cyberlab/keys"

if [[ -z "$LABVM_IP" ]]; then
    echo "ERROR: Cannot determine Lab VM IP. Is labvm running?"
    echo "       Check with: virsh domifaddr labvm"
    exit 1
fi

if [[ ! -f "$ROOT_KEY" ]]; then
    echo "ERROR: Root SSH key not found: $ROOT_KEY"
    echo "       This key should be authorized on labvm for initial access."
    exit 1
fi

echo "Lab VM IP: $LABVM_IP"

# Test connectivity
if ! ssh -i "$ROOT_KEY" -o BatchMode=yes -o ConnectTimeout=5 root@"$LABVM_IP" echo ok &>/dev/null; then
    echo "ERROR: Cannot SSH to labvm as root"
    echo "       Ensure portainer_labvm.pub is in labvm's /root/.ssh/authorized_keys"
    exit 1
fi

# ============================================================================
# PHASE 1: Setup admin/instructor SSH keys for Lab VM
# ============================================================================
echo "[1/5] Setting up admin/instructor SSH keys for Lab VM..."

mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

# Users that need labvm access: VDS user -> labvm user
declare -A LABVM_USERS=(
    ["admin1"]="labadmin1"
    ["admin2"]="labadmin2"
    ["admin3"]="labadmin3"
    ["instructor1"]="instructor1"
    ["instructor2"]="instructor2"
)

for vds_user in "${!LABVM_USERS[@]}"; do
    labvm_user="${LABVM_USERS[$vds_user]}"
    key_file="/home/${vds_user}/.ssh/labvm_key"
    
    # Skip if VDS user doesn't exist
    if ! id "$vds_user" &>/dev/null; then
        echo "  Skipping $vds_user (user doesn't exist on VDS)"
        continue
    fi
    
    # Generate key if it doesn't exist
    if [[ ! -f "$key_file" ]]; then
        echo "  Generating SSH key for $vds_user -> $labvm_user"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "${vds_user}@vds-to-labvm" -q
        chown "${vds_user}:${vds_user}" "$key_file" "${key_file}.pub"
        chmod 600 "$key_file"
    else
        echo "  Key exists for $vds_user"
    fi
    
    # Copy public key to labvm
    echo "  Copying public key to labvm:${labvm_user}"
    pubkey=$(cat "${key_file}.pub")
    ssh -i "$ROOT_KEY" -o BatchMode=yes root@"$LABVM_IP" \
        "mkdir -p /home/${labvm_user}/.ssh && \
         grep -qF '${pubkey}' /home/${labvm_user}/.ssh/authorized_keys 2>/dev/null || \
         echo '${pubkey}' >> /home/${labvm_user}/.ssh/authorized_keys && \
         chmod 700 /home/${labvm_user}/.ssh && \
         chmod 600 /home/${labvm_user}/.ssh/authorized_keys && \
         chown -R ${labvm_user}:${labvm_user} /home/${labvm_user}/.ssh"
done

# ============================================================================
# PHASE 2: Create global labvm.conf SSH config
# ============================================================================
echo "[2/5] Creating /etc/ssh/ssh_config.d/labvm.conf..."

mkdir -p /etc/ssh/ssh_config.d

cat > /etc/ssh/ssh_config.d/labvm.conf << EOF
# ============================================================================
# VTCS Cyber Range - Lab VM SSH Configuration
# ============================================================================
# Enables 'ssh labvm' shortcut for all users
# Each user connects as their corresponding labvm user
# ============================================================================

Host labvm
    HostName ${LABVM_IP}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

# Admin mappings
Match host labvm user admin1
    User labadmin1
    IdentityFile ~/.ssh/labvm_key

Match host labvm user admin2
    User labadmin2
    IdentityFile ~/.ssh/labvm_key

Match host labvm user admin3
    User labadmin3
    IdentityFile ~/.ssh/labvm_key

# Instructor mappings
Match host labvm user instructor1
    User instructor1
    IdentityFile ~/.ssh/labvm_key

Match host labvm user instructor2
    User instructor2
    IdentityFile ~/.ssh/labvm_key

# Root/ForceCommand uses shared key
Match host labvm user root
    User root
    IdentityFile /root/.ssh/portainer_labvm

# Fallback for ForceCommand (runs as student user, needs shared key)
Match host labvm
    User root
    IdentityFile /etc/cyberlab/keys/labvm_key
EOF

chmod 644 /etc/ssh/ssh_config.d/labvm.conf

# Create shared key for ForceCommand if it doesn't exist
if [[ ! -f "$KEYS_DIR/labvm_key" ]]; then
    echo "  Creating shared ForceCommand key..."
    ssh-keygen -t ed25519 -f "$KEYS_DIR/labvm_key" -N "" -C "forcecommand@vds" -q
    chmod 600 "$KEYS_DIR/labvm_key"
    
    # Add to labvm root authorized_keys
    pubkey=$(cat "$KEYS_DIR/labvm_key.pub")
    ssh -i "$ROOT_KEY" -o BatchMode=yes root@"$LABVM_IP" \
        "grep -qF '${pubkey}' /root/.ssh/authorized_keys 2>/dev/null || \
         echo '${pubkey}' >> /root/.ssh/authorized_keys"
fi

# ============================================================================
# PHASE 3: Create student users
# ============================================================================
echo "[3/5] Creating student users..."

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
echo "[4/5] Configuring sshd for students..."

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
echo "[5/5] Testing sshd configuration..."
if sshd -t; then
    echo "  sshd config OK, reloading..."
    systemctl reload sshd
else
    echo "ERROR: sshd config test failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "SSH & Student setup complete!"
echo "=========================================="
echo ""
echo "Lab VM SSH configured:"
echo "  - Admin/instructor keys generated and copied to labvm"
echo "  - 'ssh labvm' now works for: admin1/2/3, instructor1/2"
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
echo "Test admin/instructor access: ssh labvm (as admin1/2/3 or instructor1/2)"
echo "Students connect: ssh -i <key> <user>@10.200.0.1"
echo ""
