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
        start|stop|restart|status|reset|logs|shell|build|ssh-info)
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
    *)
        log_error "Unknown command: $COMMAND"
        print_usage
        exit 1
        ;;
esac
