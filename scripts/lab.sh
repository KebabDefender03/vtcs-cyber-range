#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Phase Control Script
# ============================================================================
# Controls network access phases for the cyber range lab.
# Usage: ./lab.sh <prep|combat|phase>
#
# Note: Container management (start/stop/logs/shell) is done via Portainer.
# This script ONLY handles phase control (iptables rules).
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Phase control configuration
PHASE_FILE="/tmp/cyberlab-phase"
RED_NET="172.20.2.0/24"
BLUE_NET="172.20.1.0/24"
SERVICES_NET="172.20.3.0/24"
DOCKER_NETS="172.20.0.0/16"

# SSH to Lab VM (run from VDS)
LABVM_IP="192.168.122.10"
LABVM_KEY="/root/.ssh/portainer_labvm"

print_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║             VTCS CYBER RANGE - PHASE CONTROL                       ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  prep      Preparation phase: Internet ON, cross-team attacks OFF"
    echo "  combat    Combat phase: Internet OFF, cross-team attacks ON"
    echo "  phase     Show current phase status"
    echo ""
    echo "Examples:"
    echo "  sudo $0 prep      # Enable preparation phase"
    echo "  sudo $0 combat    # Enable combat phase"
    echo "  sudo $0 phase     # Check current phase"
    echo ""
    echo "Note: Container management is done via Portainer (https://10.200.0.1:9443)"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on VDS or Lab VM
detect_environment() {
    if [[ -f "$LABVM_KEY" ]]; then
        echo "vds"
    else
        echo "labvm"
    fi
}

# Execute iptables command (locally or via SSH to Lab VM)
run_iptables() {
    local env=$(detect_environment)
    
    if [[ "$env" == "vds" ]]; then
        # Running on VDS - SSH to Lab VM
        ssh -i "$LABVM_KEY" -o StrictHostKeyChecking=no root@"$LABVM_IP" "$@"
    else
        # Running directly on Lab VM
        eval "$@"
    fi
}

cmd_prep() {
    log_info "Activating PREPARATION phase..."
    echo ""
    echo -e "${YELLOW}┌────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│         PREPARATION PHASE                  │${NC}"
    echo -e "${YELLOW}│  • Internet access: ENABLED                │${NC}"
    echo -e "${YELLOW}│  • Cross-team attacks: DISABLED            │${NC}"
    echo -e "${YELLOW}│  • Students can download tools             │${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Clear any existing phase rules
    run_iptables "iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o eth0 -j DROP 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true"
    # Clear services routing rules
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    
    # PREP: Enable internet (NAT masquerade)
    log_info "Enabling internet access for containers..."
    run_iptables "iptables -t nat -A POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE"
    # Ensure Docker per-network MASQUERADE rules exist (Docker usually creates these, but restore if missing)
    run_iptables "iptables -t nat -C POSTROUTING -s ${RED_NET} ! -o br-red -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${RED_NET} ! -o br-red -j MASQUERADE"
    run_iptables "iptables -t nat -C POSTROUTING -s ${BLUE_NET} ! -o br-blue -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${BLUE_NET} ! -o br-blue -j MASQUERADE"
    
    # PREP: Block cross-team traffic
    log_info "Blocking cross-team attacks..."
    run_iptables "iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP"
    run_iptables "iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP"
    
    # PREP: Allow access to services (students not on services_net, need routing)
    log_info "Enabling access to services network..."
    run_iptables "iptables -I FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT"
    
    # Save phase state
    echo "prep" > ${PHASE_FILE}
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> ${PHASE_FILE}
    
    log_info "Preparation phase ACTIVE"
    echo ""
    echo "Students can now download tools. Run '$0 combat' when ready to begin."
}

cmd_combat() {
    log_info "Activating COMBAT phase..."
    echo ""
    echo -e "${RED}┌────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│            COMBAT PHASE                    │${NC}"
    echo -e "${RED}│  • Internet access: DISABLED               │${NC}"
    echo -e "${RED}│  • Cross-team attacks: ENABLED             │${NC}"
    echo -e "${RED}│  • Red vs Blue - FIGHT!                    │${NC}"
    echo -e "${RED}└────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Clear any existing phase rules
    run_iptables "iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o eth0 -j DROP 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true"
    # Clear services routing rules
    run_iptables "iptables -D FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true"
    run_iptables "iptables -D FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true"
    
    # COMBAT: Disable internet (NAT rule already removed above, now block egress)
    log_info "Disabling internet access..."
    run_iptables "iptables -I FORWARD -s ${DOCKER_NETS} ! -d ${DOCKER_NETS} -o eth0 -j DROP"
    # Remove Docker's per-bridge MASQUERADE rules (created automatically by Docker)
    run_iptables "iptables -t nat -D POSTROUTING -s ${RED_NET} ! -o br-red -j MASQUERADE 2>/dev/null || true"
    run_iptables "iptables -t nat -D POSTROUTING -s ${BLUE_NET} ! -o br-blue -j MASQUERADE 2>/dev/null || true"
    
    # COMBAT: Enable cross-team traffic
    log_info "Enabling cross-team attacks..."
    run_iptables "iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT"
    
    # COMBAT: Allow access to services (students not on services_net, need routing)
    log_info "Enabling access to services network..."
    run_iptables "iptables -I FORWARD -s ${RED_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${BLUE_NET} -d ${SERVICES_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${SERVICES_NET} -d ${RED_NET} -j ACCEPT"
    run_iptables "iptables -I FORWARD -s ${SERVICES_NET} -d ${BLUE_NET} -j ACCEPT"
    
    # Save phase state
    echo "combat" > ${PHASE_FILE}
    echo "$(date '+%Y-%m-%d %H:%M:%S')" >> ${PHASE_FILE}
    
    log_info "Combat phase ACTIVE"
    echo ""
    echo -e "${RED}⚔️  LET THE BATTLE BEGIN! ⚔️${NC}"
}

cmd_phase() {
    echo -e "${BLUE}=== Current Phase Status ===${NC}"
    echo ""
    
    if [[ -f ${PHASE_FILE} ]]; then
        current_phase=$(head -1 ${PHASE_FILE})
        phase_time=$(tail -1 ${PHASE_FILE})
        
        if [[ "$current_phase" == "prep" ]]; then
            echo -e "Current Phase: ${YELLOW}PREPARATION${NC}"
            echo "  • Internet: ENABLED"
            echo "  • Cross-team: BLOCKED"
        elif [[ "$current_phase" == "combat" ]]; then
            echo -e "Current Phase: ${RED}COMBAT${NC}"
            echo "  • Internet: DISABLED"
            echo "  • Cross-team: ENABLED"
        fi
        echo ""
        echo "Phase activated: ${phase_time}"
    else
        echo -e "Current Phase: ${NC}UNKNOWN (no phase set)${NC}"
        echo ""
        echo "Run '$0 prep' to start preparation phase"
        echo "Run '$0 combat' to start combat phase"
    fi
    
    echo ""
    echo -e "${BLUE}=== Network Rules (Lab VM) ===${NC}"
    
    local env=$(detect_environment)
    echo "NAT (internet):"
    if [[ "$env" == "vds" ]]; then
        ssh -i "$LABVM_KEY" -o StrictHostKeyChecking=no root@"$LABVM_IP" \
            "iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E 'MASQUERADE|172.20' || echo '  No NAT rules'"
        echo ""
        echo "Forward (cross-team):"
        ssh -i "$LABVM_KEY" -o StrictHostKeyChecking=no root@"$LABVM_IP" \
            "iptables -L FORWARD -n 2>/dev/null | grep -E '172.20' | head -4 || echo '  No cross-team rules'"
    else
        iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E "MASQUERADE|172.20" || echo "  No NAT rules"
        echo ""
        echo "Forward (cross-team):"
        iptables -L FORWARD -n 2>/dev/null | grep -E "172.20" | head -4 || echo "  No cross-team rules"
    fi
}

# Main
print_banner

case "${1:-}" in
    prep)       cmd_prep ;;
    combat)     cmd_combat ;;
    phase)      cmd_phase ;;
    -h|--help)  print_usage ;;
    *)
        print_usage
        exit 1
        ;;
esac
