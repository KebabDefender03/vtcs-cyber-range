#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Add New Student Script
# ============================================================================
# Usage: sudo ./add-student.sh <red|blue> <number>
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WG_CONF="/etc/wireguard/wg0.conf"
SSHD_CONF="/etc/ssh/sshd_config.d/50-vpn-restrictions.conf"
VPN_CONFIGS_DIR="/opt/cyberlab/vpn-configs"
SERVER_ENDPOINT="62.171.146.215:51820"

usage() {
    echo -e "${BLUE}VTCS Cyber Range - Add New Student${NC}"
    echo ""
    echo "Usage: $0 <team> <number>"
    echo ""
    echo "Examples:"
    echo "  $0 red 4     # Creates red4"
    echo "  $0 blue 4    # Creates blue4"
    exit 1
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $# -ne 2 ]]; then usage; fi

TEAM="$1"
NUM="$2"

if [[ "$TEAM" != "red" && "$TEAM" != "blue" ]]; then
    log_error "Team must be 'red' or 'blue'"; exit 1
fi

if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [[ "$NUM" -lt 1 ]] || [[ "$NUM" -gt 10 ]]; then
    log_error "Number must be between 1 and 10"; exit 1
fi

if [[ "$TEAM" == "red" ]]; then
    VPN_IP="10.200.0.$((99 + NUM))"
else
    VPN_IP="10.200.0.$((109 + NUM))"
fi

STUDENT_NAME="${TEAM}${NUM}"
CONFIG_FILE="${VPN_CONFIGS_DIR}/${STUDENT_NAME}.conf"
PACKAGE_DIR="/opt/cyberlab/student-packages/${STUDENT_NAME}"

log_info "Adding student: ${STUDENT_NAME} (VPN: ${VPN_IP})"

if id "$STUDENT_NAME" &>/dev/null; then
    log_error "User ${STUDENT_NAME} already exists!"; exit 1
fi

# 1. CREATE USER (key-only)
log_info "Creating VDS user..."
useradd -m -s /bin/bash "$STUDENT_NAME"
passwd -l "$STUDENT_NAME"

# 2. GENERATE SSH KEY
log_info "Generating SSH keypair..."
mkdir -p /home/${STUDENT_NAME}/.ssh
ssh-keygen -t ed25519 -f /home/${STUDENT_NAME}/.ssh/id_ed25519 -N "" -C "${STUDENT_NAME}@cyberlab"
cp /home/${STUDENT_NAME}/.ssh/id_ed25519.pub /home/${STUDENT_NAME}/.ssh/authorized_keys
chmod 700 /home/${STUDENT_NAME}/.ssh
chmod 600 /home/${STUDENT_NAME}/.ssh/id_ed25519 /home/${STUDENT_NAME}/.ssh/authorized_keys
chown -R ${STUDENT_NAME}:${STUDENT_NAME} /home/${STUDENT_NAME}/.ssh

# 3. WIREGUARD
log_info "Configuring WireGuard..."
WG_PRIVATE=$(wg genkey)
WG_PUBLIC=$(echo "$WG_PRIVATE" | wg pubkey)
SERVER_PUBLIC=$(wg show wg0 public-key)

cat >> "$WG_CONF" << PEER

# Student ${STUDENT_NAME^}
[Peer]
PublicKey = ${WG_PUBLIC}
AllowedIPs = ${VPN_IP}/32
PEER

mkdir -p "$VPN_CONFIGS_DIR"
cat > "$CONFIG_FILE" << CONF
[Interface]
PrivateKey = ${WG_PRIVATE}
Address = ${VPN_IP}/24
DNS = 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC}
AllowedIPs = 10.200.0.0/24, 192.168.122.0/24, 172.20.0.0/16
Endpoint = ${SERVER_ENDPOINT}
PersistentKeepalive = 25
CONF
chmod 600 "$CONFIG_FILE"
wg syncconf wg0 <(wg-quick strip wg0)

# 4. SSH RESTRICTIONS
log_info "Configuring SSH restrictions..."

# VPN IP restriction (only allow this user from their VPN IP)
cat >> "$SSHD_CONF" << SSHVPN

# ${STUDENT_NAME^} VPN (${VPN_IP})
Match Address ${VPN_IP}
    AllowUsers ${STUDENT_NAME}
SSHVPN

# ForceCommand to container (same drop-in file as 06-student-setup.sh)
cat >> /etc/ssh/sshd_config.d/students.conf << SSHFORCE

# ${STUDENT_NAME^}
Match User ${STUDENT_NAME}
    ForceCommand ssh -tt labvm docker exec -it ${STUDENT_NAME} bash
    PasswordAuthentication no
    PermitTTY yes
    PermitTunnel no
    AllowTcpForwarding no
    X11Forwarding no
    AllowAgentForwarding no
SSHFORCE

systemctl reload sshd

# 5. CREATE PACKAGE
log_info "Creating student package..."
mkdir -p "$PACKAGE_DIR"
cp /home/${STUDENT_NAME}/.ssh/id_ed25519 "$PACKAGE_DIR/${STUDENT_NAME}.key"
cp "$CONFIG_FILE" "$PACKAGE_DIR/"
chmod 600 "$PACKAGE_DIR/${STUDENT_NAME}.key"

cat > "$PACKAGE_DIR/README.txt" << README
VTCS Cyber Range - ${STUDENT_NAME^}
===================================

1. Install WireGuard: https://www.wireguard.com/install/
2. Import ${STUDENT_NAME}.conf into WireGuard
3. Activate VPN
4. Connect: ssh -i ${STUDENT_NAME}.key ${STUDENT_NAME}@10.200.0.1

You will automatically land in your container!
README

# 6. CREATE ZIP & COPY TO ADMIN HOMES
log_info "Creating ZIP for download..."
cd /opt/cyberlab/student-packages
zip -rq "${STUDENT_NAME}.zip" "${STUDENT_NAME}/"

# Copy to all admin home folders
for admin in admin1 admin2 admin3; do
    if [[ -d "/home/$admin" ]]; then
        cp "${STUDENT_NAME}.zip" "/home/$admin/"
        chown $admin:$admin "/home/$admin/${STUDENT_NAME}.zip"
    fi
done

# SUMMARY
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Student ${STUDENT_NAME} created!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next: Create container in Portainer${NC}"
echo "  - Clone ${TEAM}1, rename to ${STUDENT_NAME}, connect to ${TEAM}_net"
echo ""
echo -e "${YELLOW}Download the student package (from your PC with VPN on):${NC}"
echo ""
echo -e "  ${BLUE}scp -i host_admin1.key admin1@10.200.0.1:~/${STUDENT_NAME}.zip .${NC}"
echo ""
