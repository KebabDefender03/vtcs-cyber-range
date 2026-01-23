#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Lab Management Script
# ============================================================================
# Main entry point for managing the cyber range lab environment.
# Usage: ./lab.sh <command> [options]
# ============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/../scenarios"
DEFAULT_SCENARIO="base"
COMPOSE_FILE="${SCENARIOS_DIR}/${DEFAULT_SCENARIO}/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║             VTCS CYBER RANGE - LAB MANAGEMENT                      ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start       Start the lab environment"
    echo "  stop        Stop the lab environment"
    echo "  restart     Restart the lab environment"
    echo "  status      Show status of all containers"
    echo "  reset       Reset lab to clean state (destroys data!)"
    echo "  logs        Show logs (optionally for specific container)"
    echo "  shell       Open shell in a container"
    echo "  build       Build/rebuild container images"
    echo "  ssh-info    Show SSH connection info for workspaces"
    echo ""
    echo "Phase Control:"
    echo "  prep        Preparation phase: Internet ON, cross-team attacks OFF"
    echo "  combat      Combat phase: Internet OFF, cross-team attacks ON"
    echo "  phase       Show current phase status"
    echo ""
    echo "Options:"
    echo "  -s, --scenario <name>   Use specific scenario (default: base)"
    echo "  -c, --container <name>  Target specific container"
    echo "  -f, --follow            Follow log output"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start default scenario"
    echo "  $0 status                   # Show all container status"
    echo "  $0 logs -c webapp -f        # Follow webapp logs"
    echo "  $0 shell -c red1            # Open shell in red1 workspace"
    echo "  $0 reset                    # Reset to clean state"
    echo "  $0 prep                     # Enable preparation phase"
    echo "  $0 combat                   # Enable combat phase"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or you don't have permission"
        exit 1
    fi
}

cmd_start() {
    log_info "Starting lab environment..."
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    
    # Copy .env.example if .env doesn't exist
    if [[ ! -f .env ]] && [[ -f .env.example ]]; then
        log_warn "No .env file found, copying from .env.example"
        cp .env.example .env
    fi
    
    docker compose up -d
    
    log_info "Lab environment started!"
    echo ""
    cmd_status
}

cmd_stop() {
    log_info "Stopping lab environment..."
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    docker compose down
    log_info "Lab environment stopped"
}

cmd_restart() {
    log_info "Restarting lab environment..."
    cmd_stop
    cmd_start
}

cmd_status() {
    echo -e "${BLUE}=== Container Status ===${NC}"
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    docker compose ps -a
    
    echo ""
    echo -e "${BLUE}=== Network Status ===${NC}"
    docker network ls --filter "name=base_" 2>/dev/null || docker network ls | grep -E "blue|red|services" || true
    
    echo ""
    echo -e "${BLUE}=== Resource Usage ===${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "No running containers"
}

cmd_reset() {
    echo -e "${RED}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                    ⚠️  WARNING ⚠️                                    ║"
    echo "║  This will destroy ALL lab data including:                         ║"
    echo "║  - Workspace home directories                                      ║"
    echo "║  - Database contents                                               ║"
    echo "║  - Any files created by students                                   ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    read -p "Are you sure you want to reset? Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Reset cancelled"
        exit 0
    fi
    
    log_info "Resetting lab environment..."
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    
    # Stop and remove containers, networks, volumes
    docker compose down -v --remove-orphans
    
    # Optionally rebuild images
    read -p "Rebuild container images? [y/N]: " rebuild
    if [[ "$rebuild" =~ ^[Yy]$ ]]; then
        docker compose build --no-cache
    fi
    
    log_info "Lab reset complete. Run '$0 start' to start fresh."
}

cmd_logs() {
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    
    if [[ -n "${CONTAINER:-}" ]]; then
        if [[ "${FOLLOW:-}" == "true" ]]; then
            docker compose logs -f "$CONTAINER"
        else
            docker compose logs "$CONTAINER"
        fi
    else
        if [[ "${FOLLOW:-}" == "true" ]]; then
            docker compose logs -f
        else
            docker compose logs --tail=100
        fi
    fi
}

cmd_shell() {
    if [[ -z "${CONTAINER:-}" ]]; then
        log_error "Container name required. Use: $0 shell -c <container>"
        echo "Available containers:"
        cd "${SCENARIOS_DIR}/${SCENARIO}"
        docker compose ps --format "  - {{.Name}}"
        exit 1
    fi
    
    log_info "Opening shell in ${CONTAINER}..."
    docker exec -it "$CONTAINER" /bin/bash
}

cmd_build() {
    log_info "Building container images..."
    cd "${SCENARIOS_DIR}/${SCENARIO}"
    docker compose build
    log_info "Build complete"
}

# ============================================================================
# PHASE CONTROL FUNCTIONS
# ============================================================================
# Controls network access between phases:
# - Preparation: Internet ON, cross-team attacks OFF
# - Combat: Internet OFF, cross-team attacks ON
# ============================================================================

PHASE_FILE="/tmp/cyberlab-phase"
RED_NET="172.20.2.0/24"
BLUE_NET="172.20.1.0/24"
DOCKER_NETS="172.20.0.0/16"

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
    iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true
    iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true
    
    # PREP: Enable internet (NAT masquerade)
    log_info "Enabling internet access for containers..."
    iptables -t nat -A POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE
    
    # PREP: Block cross-team traffic
    log_info "Blocking cross-team attacks..."
    iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP
    iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP
    
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
    iptables -t nat -D POSTROUTING -s ${DOCKER_NETS} -o eth0 -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s ${RED_NET} -d ${BLUE_NET} -j DROP 2>/dev/null || true
    iptables -D FORWARD -s ${BLUE_NET} -d ${RED_NET} -j DROP 2>/dev/null || true
    
    # COMBAT: Disable internet (remove NAT)
    log_info "Disabling internet access..."
    # NAT rule already removed above
    
    # COMBAT: Enable cross-team traffic
    log_info "Enabling cross-team attacks..."
    iptables -I FORWARD -s ${RED_NET} -d ${BLUE_NET} -j ACCEPT
    iptables -I FORWARD -s ${BLUE_NET} -d ${RED_NET} -j ACCEPT
    
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
    echo -e "${BLUE}=== Network Rules ===${NC}"
    echo "NAT (internet):"
    iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E "MASQUERADE|172.20" || echo "  No NAT rules"
    echo ""
    echo "Forward (cross-team):"
    iptables -L FORWARD -n 2>/dev/null | grep -E "172.20" | head -4 || echo "  No cross-team rules"
}

cmd_ssh_info() {
    echo -e "${BLUE}=== SSH Connection Information ===${NC}"
    echo ""
    echo "From the Lab VM, connect to workspaces using:"
    echo ""
    
    # Get container IPs
    for workspace in blue1 blue2 blue3 red1 red2 red3; do
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$workspace" 2>/dev/null || echo "not running")
        echo "  $workspace: ssh student@$ip"
    done
    
    echo ""
    echo "Default credentials:"
    echo "  Username: student"
    echo "  Password: student"
    echo ""
    echo "Note: Change passwords after first login!"
}

# Parse arguments
SCENARIO="${DEFAULT_SCENARIO}"
CONTAINER=""
FOLLOW="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scenario)
            SCENARIO="$2"
            shift 2
            ;;
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -f|--follow)
            FOLLOW="true"
            shift
            ;;
        -h|--help)
            print_banner
            print_usage
            exit 0
            ;;
        start|stop|restart|status|reset|logs|shell|build|ssh-info|prep|combat|phase)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Main
print_banner
check_docker

if [[ -z "${COMMAND:-}" ]]; then
    print_usage
    exit 1
fi

# Update compose file path based on scenario
COMPOSE_FILE="${SCENARIOS_DIR}/${SCENARIO}/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Scenario '${SCENARIO}' not found at ${COMPOSE_FILE}"
    exit 1
fi

# Execute command
case $COMMAND in
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_restart ;;
    status)     cmd_status ;;
    reset)      cmd_reset ;;
    logs)       cmd_logs ;;
    shell)      cmd_shell ;;
    build)      cmd_build ;;
    ssh-info)   cmd_ssh_info ;;
    prep)       cmd_prep ;;
    combat)     cmd_combat ;;
    phase)      cmd_phase ;;
    *)
        log_error "Unknown command: $COMMAND"
        print_usage
        exit 1
        ;;
esac
