#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - Lab VM Bootstrap
# ============================================================================
# Run this script on the Lab VM after Ubuntu installation.
# Installs Docker, configures networking, and prepares for lab scenarios.
#
# Prerequisites:
# - Ubuntu Server 24.04 installed
# - Network connectivity (NAT via host)
# - SSH access working
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "VTCS Cyber Range - Lab VM Bootstrap"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

# Update system
echo "[1/6] Updating system packages..."
apt update && apt upgrade -y

# Install prerequisites
echo "[2/6] Installing prerequisites..."
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    vim \
    tmux \
    jq \
    make

# Install Docker
echo "[3/6] Installing Docker Engine..."
# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add lab admin users to docker group
echo "[4/6] Configuring Docker daemon and users..."

# Create lab admin users on Lab VM (matching VDS users)
for i in 1 2 3; do
    username="labadmin${i}"
    if ! id "${username}" &>/dev/null; then
        useradd -m -s /bin/bash "${username}"
        usermod -aG docker "${username}"
        echo "  Created user '${username}'"
    else
        usermod -aG docker "${username}" 2>/dev/null || true
    fi
done

# Instructor users on Lab VM
for i in 1 2; do
    username="instructor${i}"
    if ! id "${username}" &>/dev/null; then
        useradd -m -s /bin/bash "${username}"
        usermod -aG docker "${username}"
        echo "  Created user '${username}'"
    else
        usermod -aG docker "${username}" 2>/dev/null || true
    fi
done

mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-address-pools": [
        {"base": "172.20.0.0/16", "size": 24}
    ],
    "iptables": true,
    "live-restore": true
}
EOF

systemctl restart docker

# Configure Lab VM firewall
echo "[5/6] Configuring Lab VM firewall..."
apt install -y nftables

cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
# ============================================================================
# Lab VM Firewall Rules
# ============================================================================
# Controls traffic between lab networks and to/from the VM

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow established connections
        ct state established,related accept
        
        # Allow loopback
        iif lo accept
        
        # Allow ICMP
        ip protocol icmp accept
        
        # Allow SSH from host network (192.168.122.0/24) and VPN (10.200.0.0/24)
        ip saddr { 192.168.122.0/24, 10.200.0.0/24 } tcp dport 22 accept
        
        # Allow Docker bridge traffic
        iifname "docker0" accept
        iifname "br-*" accept
        
        # Log dropped
        log prefix "[LABVM DROP] " counter drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Allow established
        ct state established,related accept
        
        # Docker manages its own forwarding rules via iptables
        # Allow forwarding on Docker bridges
        iifname "docker0" accept
        oifname "docker0" accept
        iifname "br-*" accept
        oifname "br-*" accept
        
        # Log dropped forwards
        log prefix "[LABVM FWD DROP] " counter drop
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

systemctl enable nftables
systemctl restart nftables

# Create lab directory structure
echo "[6/6] Creating lab directory structure..."
mkdir -p /opt/cyberlab/{scenarios,scripts,data,logs}

# Set ownership for all lab admin users
chown -R root:docker /opt/cyberlab
chmod -R 775 /opt/cyberlab

# Clone or copy scenarios (placeholder)
cat > /opt/cyberlab/README.md << 'EOF'
# VTCS Cyber Range Lab VM

This VM hosts the Docker-based lab environment.
Containers are deployed via Portainer from GitHub (not locally).

## Directory Structure
- `/opt/cyberlab/data/` - Persistent data (databases, etc.)
- `/opt/cyberlab/logs/` - Log files

## Container Management
All container operations are done via Portainer:
- Access: https://10.200.0.1:9443 (VPN required)
- Deploy: Stacks → Add stack → Repository
- Restart: Containers → select → Restart
- Logs: Containers → select → Logs

## Network Layout
- blue_net: 172.20.1.0/24 (Blue team workspaces)
- red_net: 172.20.2.0/24 (Red team workspaces)
- services_net: 172.20.3.0/24 (Target services)
EOF

chmod 644 /opt/cyberlab/README.md

echo ""
echo "=========================================="
echo "Lab VM bootstrap complete!"
echo "=========================================="
echo ""
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo ""
echo "Lab directory: /opt/cyberlab/"
echo ""
echo "NEXT STEPS:"
echo "1. Deploy Portainer Agent on this VM"
echo "2. Add this VM as endpoint in Portainer (VDS host)"
echo "3. Deploy stack from GitHub via Portainer"
echo ""
echo "Note: Log out and back in for docker group membership to apply,"
echo "or run: newgrp docker"
echo ""
