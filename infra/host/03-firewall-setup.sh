#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - Host Firewall Setup (nftables)
# ============================================================================
# Locks down the host to VPN-only access. After running this script:
# - Only WireGuard port (51820/UDP) is accessible from the internet
# - SSH (22) and Cockpit (9090) only accessible from VPN subnet
# - All other inbound traffic is dropped
#
# Security rationale:
# - Defense in depth: even if services have vulnerabilities, they're not exposed
# - VPN acts as first authentication layer before any service access
# - Explicit allowlist approach (default deny)
# ============================================================================

set -euo pipefail

# Configuration
WG_PORT="51820"
WG_SUBNET="10.200.0.0/24"
LABVM_SUBNET="192.168.122.0/24"  # Default libvirt NAT network

# Management access IP ranges (must match VPN IP assignments)
# See docs/security.md for IP allocation scheme
ADMIN_RANGE="10.200.0.10-10.200.0.19"       # Reserved for admins (currently .10-.12)
INSTRUCTOR_RANGE="10.200.0.20-10.200.0.29"  # Reserved for instructors (currently .20-.21)

echo "=========================================="
echo "VTCS Cyber Range - Host Firewall Setup"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Install nftables if not present
apt install -y nftables

# Backup existing rules
echo "[1/5] Backing up existing firewall rules..."
nft list ruleset > /root/nftables-backup-$(date +%Y%m%d-%H%M%S).conf 2>/dev/null || true

# Create nftables configuration
echo "[2/5] Creating nftables firewall rules..."
cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f
# ============================================================================
# VTCS Cyber Range - Host Firewall Rules (nftables)
# ============================================================================
# Default policy: DROP all inbound, ACCEPT outbound
# Only WireGuard is exposed to the internet
# Management services only accessible via VPN
# ============================================================================

flush ruleset

table inet filter {
    # ========================================================================
    # INPUT chain - traffic TO this host
    # ========================================================================
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established/related connections (return traffic)
        ct state established,related accept

        # Allow loopback
        iif lo accept

        # Allow ICMP (ping) - useful for diagnostics
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # === INTERNET-FACING (minimal exposure) ===
        # WireGuard VPN - ONLY port exposed to internet
        udp dport ${WG_PORT} accept comment "WireGuard VPN"

        # === VPN-ONLY ACCESS (restricted to admins and instructors) ===
        # SSH - only from VPN clients (all users can SSH to their assigned user)
        iifname "wg0" tcp dport 22 accept comment "SSH via VPN only"
        
        # Cockpit - only admins and instructors (not students)
        iifname "wg0" ip saddr ${ADMIN_RANGE} tcp dport 9090 accept comment "Cockpit - admins"
        iifname "wg0" ip saddr ${INSTRUCTOR_RANGE} tcp dport 9090 accept comment "Cockpit - instructors"
        
        # Portainer - only admins and instructors (not students)
        # NOTE: These nftables rules are ineffective for Docker containers (DNAT bypass)
        # Actual Portainer filtering is done via iptables DOCKER-USER chain below
        iifname "wg0" ip saddr ${ADMIN_RANGE} tcp dport 9443 accept comment "Portainer - admins"
        iifname "wg0" ip saddr ${INSTRUCTOR_RANGE} tcp dport 9443 accept comment "Portainer - instructors"

        # Allow traffic from lab VM network (for host services if needed)
        # But block Lab VM from accessing management ports
        iifname "virbr0" ip saddr ${LABVM_SUBNET} tcp dport { 22, 9090, 9443 } drop comment "Block Lab VM from management"
        iifname "virbr0" accept comment "Lab VM network"

        # Log and drop everything else
        log prefix "[nftables DROP INPUT] " flags all counter drop
    }

    # ========================================================================
    # FORWARD chain - traffic THROUGH this host (routing)
    # ========================================================================
    chain forward {
        type filter hook forward priority 0; policy drop;

        # Allow established/related
        ct state established,related accept

        # Allow VPN clients to reach lab VM network
        ip saddr ${WG_SUBNET} ip daddr ${LABVM_SUBNET} accept comment "VPN to Lab VM"
        
        # Allow lab VM to respond to VPN clients
        ip saddr ${LABVM_SUBNET} ip daddr ${WG_SUBNET} accept comment "Lab VM to VPN"

        # Allow lab VM to reach internet (for apt updates, etc.)
        # This is controlled at runtime by lab.sh (prep/combat phases)
        iifname "virbr0" oifname != "wg0" accept comment "Lab VM to internet"
        oifname "virbr0" iifname != "wg0" ct state established,related accept comment "Internet to Lab VM (established)"

        # Log dropped forwards
        log prefix "[nftables DROP FORWARD] " flags all counter drop
    }

    # ========================================================================
    # OUTPUT chain - traffic FROM this host
    # ========================================================================
    chain output {
        type filter hook output priority 0; policy accept;
        # Allow all outbound (host needs updates, DNS, etc.)
        # In stricter environments, this could be limited too
    }
}

# ============================================================================
# NAT table - for lab VM internet access (if needed, controlled)
# ============================================================================
table inet nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        
        # Masquerade lab VM traffic going to internet (if allowed)
        ip saddr ${LABVM_SUBNET} oifname != "virbr0" masquerade
        
        # Masquerade VPN client traffic if they need internet via VPN
        ip saddr ${WG_SUBNET} oifname != "wg0" masquerade
    }
}
EOF

# Enable and start nftables
echo "[3/5] Enabling nftables service..."
systemctl enable nftables
systemctl restart nftables

# Verify rules are loaded
echo "[4/5] Verifying firewall rules..."
nft list ruleset

# ============================================================================
# Docker Portainer Access Control (iptables DOCKER-USER chain)
# ============================================================================
# nftables cannot block traffic to Docker containers because Docker uses DNAT
# in PREROUTING chain before nftables INPUT is evaluated. We must use iptables
# DOCKER-USER chain to filter traffic to Portainer (port 9443).
# ============================================================================
echo ""
echo "[5/5] Configuring Docker Portainer access control..."

# Clear existing DOCKER-USER rules (flush all, then re-add RETURN)
iptables -F DOCKER-USER 2>/dev/null || true

# Allow admins and instructors (10.200.0.10-29) to access Portainer
iptables -A DOCKER-USER -i wg0 -m iprange --src-range 10.200.0.10-10.200.0.29 -p tcp --dport 9443 -j ACCEPT

# Block all other VPN traffic to Portainer (students are 10.200.0.100+)
iptables -A DOCKER-USER -i wg0 -p tcp --dport 9443 -j DROP

# Return for all other traffic (required for Docker to function)
iptables -A DOCKER-USER -j RETURN

# Save iptables rules for persistence
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "  - Portainer (9443): Allowed for 10.200.0.10-29 (admins/instructors)"
echo "  - Portainer (9443): Blocked for 10.200.0.100+ (students)"

echo ""
echo "=========================================="
echo "Host firewall setup complete!"
echo "=========================================="
echo ""
echo "SECURITY STATUS:"
echo "  - Internet-exposed: Only WireGuard (UDP ${WG_PORT})"
echo "  - SSH: VPN-only (all VPN clients)"
echo "  - Cockpit: Admins (${ADMIN_RANGE}) + Instructors (${INSTRUCTOR_RANGE})"
echo "  - Portainer: Admins + Instructors only (10.200.0.10-29 via DOCKER-USER)"
echo "  - Lab VM network: ${LABVM_SUBNET}"
echo ""
echo "WARNING: Make sure you have a working VPN client config BEFORE"
echo "         disconnecting your current SSH session!"
echo ""
echo "Test VPN connectivity from another terminal before closing this one."
echo ""
