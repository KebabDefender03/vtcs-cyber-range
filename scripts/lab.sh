#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Phase Control Script (Simplified)
# ============================================================================
# Uses SUBNET-based rules - new containers (red4, blue5, etc.) work automatically!
# Usage: ./lab.sh <prep|combat|phase>
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Network subnets (not individual IPs!)
RED_NET="172.20.2.0/24"
BLUE_NET="172.20.1.0/24"
SERVICES_NET="172.20.3.0/24"
DOCKER_NETS="172.20.0.0/16"

# Lab VM SSH config
LABVM_IP="192.168.122.10"
SSH_KEY="/root/.ssh/portainer_labvm"
PHASE_FILE="/tmp/cyberlab-phase"

# Detect WAN interface (enp1s0 on Lab VM)
WAN_IF="enp1s0"

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }

# Run command on Lab VM
run_cmd() {
    if [[ -f "$SSH_KEY" ]]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$LABVM_IP" "$1"
    else
        eval "$1"
    fi
}

cmd_prep() {
    log_info "Activating PREPARATION phase..."
    echo -e "${YELLOW}┌──────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  PREP: Internet ON, Cross-team OFF       │${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────┘${NC}"

    # Clean rules
    run_cmd "iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o ${WAN_IF} -j DROP 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true"

    # Enable internet (NAT via enp1s0)
    run_cmd "iptables -t nat -A POSTROUTING -s ${DOCKER_NETS} -o ${WAN_IF} -j MASQUERADE"

    # Block cross-team
    run_cmd "iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP"
    run_cmd "iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP"

    # Allow services
    run_cmd "iptables -I FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT"

    run_cmd "echo 'prep' > ${PHASE_FILE}; date >> ${PHASE_FILE}"
    log_info "Preparation phase ACTIVE"
}

cmd_combat() {
    log_info "Activating COMBAT phase..."
    echo -e "${RED}┌──────────────────────────────────────────┐${NC}"
    echo -e "${RED}│  COMBAT: Internet OFF, Cross-team ON     │${NC}"
    echo -e "${RED}└──────────────────────────────────────────┘${NC}"

    # Clean rules
    run_cmd "iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o ${WAN_IF} -j DROP 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true"
    run_cmd "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true"

    # Block internet
    run_cmd "iptables -I FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o ${WAN_IF} -j DROP"

    # Enable cross-team
    run_cmd "iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT"

    # Allow services
    run_cmd "iptables -I FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT"
    run_cmd "iptables -I FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT"

    run_cmd "echo 'combat' > ${PHASE_FILE}; date >> ${PHASE_FILE}"
    log_info "Combat phase ACTIVE"
    echo -e "${RED}⚔️  LET THE BATTLE BEGIN! ⚔️${NC}"
}

cmd_phase() {
    echo -e "${BLUE}=== Phase Status ===${NC}"
    local phase=$(run_cmd "cat ${PHASE_FILE} 2>/dev/null | head -1")
    case "$phase" in
        prep)   echo -e "Phase: ${YELLOW}PREPARATION${NC} (Internet ON, Cross-team OFF)" ;;
        combat) echo -e "Phase: ${RED}COMBAT${NC} (Internet OFF, Cross-team ON)" ;;
        *)      echo "Phase: UNKNOWN - run '$0 prep' to start" ;;
    esac
}

print_help() {
    echo -e "${BLUE}VTCS Cyber Range - Lab Control${NC}"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "  prep    - Internet ON, Cross-team OFF"
    echo "  combat  - Internet OFF, Cross-team ON"
    echo "  phase   - Show current phase"
    echo ""
    echo "New containers (red4, blue5) work automatically!"
    echo "Just connect them to red_net or blue_net in Portainer."
}

case "${1:-}" in
    prep)    cmd_prep ;;
    combat)  cmd_combat ;;
    phase)   cmd_phase ;;
    *)       print_help ;;
esac
