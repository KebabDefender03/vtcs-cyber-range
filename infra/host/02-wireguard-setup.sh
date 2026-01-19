#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - WireGuard VPN Setup
# ============================================================================
# Configures WireGuard as the sole entry point to the host.
# After this + firewall setup, only VPN clients can access SSH/Cockpit.
#
# Security rationale:
# - VPN provides authenticated, encrypted tunnel before any service access
# - Each student/admin gets unique keys for accountability
# - Server only accepts connections from configured peers
# ============================================================================

set -euo pipefail

# Configuration
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_SUBNET="10.200.0.0/24"
WG_SERVER_IP="10.200.0.1"
WG_CONFIG_DIR="/etc/wireguard"
WG_CLIENTS_DIR="${WG_CONFIG_DIR}/clients"

echo "=========================================="
echo "VTCS Cyber Range - WireGuard VPN Setup"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Create directories
mkdir -p "${WG_CLIENTS_DIR}"
chmod 700 "${WG_CONFIG_DIR}"

# Generate server keys if they don't exist
if [[ ! -f "${WG_CONFIG_DIR}/server_private.key" ]]; then
    echo "[1/4] Generating server keys..."
    wg genkey | tee "${WG_CONFIG_DIR}/server_private.key" | wg pubkey > "${WG_CONFIG_DIR}/server_public.key"
    chmod 600 "${WG_CONFIG_DIR}/server_private.key"
else
    echo "[1/4] Server keys already exist, skipping..."
fi

SERVER_PRIVATE_KEY=$(cat "${WG_CONFIG_DIR}/server_private.key")
SERVER_PUBLIC_KEY=$(cat "${WG_CONFIG_DIR}/server_public.key")

# Detect public IP
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
echo "    Detected public IP: ${PUBLIC_IP}"

# Create server configuration
echo "[2/4] Creating WireGuard server configuration..."
cat > "${WG_CONFIG_DIR}/${WG_INTERFACE}.conf" << EOF
# ============================================================================
# WireGuard Server Configuration - VTCS Cyber Range
# ============================================================================
# This is the main entry point to the lab environment.
# Only configured peers can establish a tunnel.
# ============================================================================

[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

# Enable IP forwarding for VPN clients to reach internal services
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i %i -j ACCEPT
PostUp = iptables -A FORWARD -o %i -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT
PostDown = iptables -D FORWARD -o %i -j ACCEPT

# Peer configurations are added below by the add-vpn-client.sh script
# Each peer gets a unique IP in the 10.200.0.0/24 range

EOF

chmod 600 "${WG_CONFIG_DIR}/${WG_INTERFACE}.conf"

# Enable and start WireGuard
echo "[3/4] Enabling WireGuard service..."
systemctl enable wg-quick@${WG_INTERFACE}
systemctl start wg-quick@${WG_INTERFACE} || systemctl restart wg-quick@${WG_INTERFACE}

# Create client generation script
echo "[4/4] Creating client management script..."
cat > "${WG_CONFIG_DIR}/add-vpn-client.sh" << 'SCRIPT'
#!/bin/bash
# Generate a new WireGuard client configuration
# Usage: ./add-vpn-client.sh <client_name> <client_ip_last_octet>
# Example: ./add-vpn-client.sh admin 10  -> gets IP 10.200.0.10

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <client_name> <client_ip_last_octet>"
    echo "Example: $0 admin 10"
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_IP_OCTET="$2"
CLIENT_IP="10.200.0.${CLIENT_IP_OCTET}"

WG_CONFIG_DIR="/etc/wireguard"
WG_CLIENTS_DIR="${WG_CONFIG_DIR}/clients"
SERVER_PUBLIC_KEY=$(cat "${WG_CONFIG_DIR}/server_public.key")
PUBLIC_IP=$(curl -s ifconfig.me)

mkdir -p "${WG_CLIENTS_DIR}/${CLIENT_NAME}"

# Generate client keys
wg genkey | tee "${WG_CLIENTS_DIR}/${CLIENT_NAME}/private.key" | wg pubkey > "${WG_CLIENTS_DIR}/${CLIENT_NAME}/public.key"
chmod 600 "${WG_CLIENTS_DIR}/${CLIENT_NAME}/private.key"

CLIENT_PRIVATE_KEY=$(cat "${WG_CLIENTS_DIR}/${CLIENT_NAME}/private.key")
CLIENT_PUBLIC_KEY=$(cat "${WG_CLIENTS_DIR}/${CLIENT_NAME}/public.key")

# Create client config file
cat > "${WG_CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.conf" << EOF
# WireGuard Client Configuration - ${CLIENT_NAME}
# VTCS Cyber Range POC
# Import this file into your WireGuard client

[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${PUBLIC_IP}:51820
AllowedIPs = 10.200.0.0/24, 192.168.122.0/24
PersistentKeepalive = 25
EOF

# Add peer to server config
cat >> "${WG_CONFIG_DIR}/wg0.conf" << EOF

# Client: ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

# Reload WireGuard to apply new peer
wg syncconf wg0 <(wg-quick strip wg0)

echo ""
echo "=========================================="
echo "Client '${CLIENT_NAME}' created!"
echo "=========================================="
echo "Client IP: ${CLIENT_IP}"
echo "Config file: ${WG_CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.conf"
echo ""
echo "Transfer the .conf file securely to the client."
echo "Do NOT send via unencrypted channels!"
echo ""
SCRIPT

chmod +x "${WG_CONFIG_DIR}/add-vpn-client.sh"

echo ""
echo "=========================================="
echo "WireGuard VPN setup complete!"
echo "=========================================="
echo "Server public key: ${SERVER_PUBLIC_KEY}"
echo "Server endpoint: ${PUBLIC_IP}:${WG_PORT}"
echo "VPN subnet: ${WG_SUBNET}"
echo ""
echo "To add VPN clients, run:"
echo "  ${WG_CONFIG_DIR}/add-vpn-client.sh <name> <ip_octet>"
echo ""
echo "Example - create admin client with IP 10.200.0.10:"
echo "  ${WG_CONFIG_DIR}/add-vpn-client.sh admin 10"
echo ""
echo "IMPORTANT: Run 03-firewall-setup.sh next to lock down access!"
echo ""
