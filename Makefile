# ============================================================================
# VTCS Cyber Range - Makefile
# ============================================================================
# Convenience targets for lab management
# ============================================================================

.PHONY: help start stop restart status reset logs build ssh-info deploy-host deploy-labvm

# Default target
help:
	@echo "VTCS Cyber Range - Available Targets"
	@echo "====================================="
	@echo ""
	@echo "Lab Management:"
	@echo "  make start      - Start the lab environment"
	@echo "  make stop       - Stop the lab environment"
	@echo "  make restart    - Restart the lab environment"
	@echo "  make status     - Show container status"
	@echo "  make reset      - Reset to clean state (destroys data!)"
	@echo "  make logs       - Show logs (use CONTAINER=name for specific)"
	@echo "  make build      - Build container images"
	@echo "  make ssh-info   - Show SSH connection info"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-host    - Deploy host setup scripts to VDS"
	@echo "  make deploy-labvm   - Deploy lab VM scripts"
	@echo ""
	@echo "Variables:"
	@echo "  SCENARIO=name   - Use specific scenario (default: base)"
	@echo "  CONTAINER=name  - Target specific container"
	@echo ""

# Configuration
SCENARIO ?= base
SCRIPTS_DIR := scripts
SCENARIOS_DIR := scenarios

# Lab management targets
start:
	@bash $(SCRIPTS_DIR)/lab.sh start -s $(SCENARIO)

stop:
	@bash $(SCRIPTS_DIR)/lab.sh stop -s $(SCENARIO)

restart:
	@bash $(SCRIPTS_DIR)/lab.sh restart -s $(SCENARIO)

status:
	@bash $(SCRIPTS_DIR)/lab.sh status -s $(SCENARIO)

reset:
	@bash $(SCRIPTS_DIR)/lab.sh reset -s $(SCENARIO)

logs:
ifdef CONTAINER
	@bash $(SCRIPTS_DIR)/lab.sh logs -s $(SCENARIO) -c $(CONTAINER) -f
else
	@bash $(SCRIPTS_DIR)/lab.sh logs -s $(SCENARIO)
endif

build:
	@bash $(SCRIPTS_DIR)/lab.sh build -s $(SCENARIO)

ssh-info:
	@bash $(SCRIPTS_DIR)/lab.sh ssh-info -s $(SCENARIO)

# Deployment targets (run from local machine)
VDS_HOST ?= 62.171.146.215
VDS_USER ?= root

deploy-host:
	@echo "Deploying host setup scripts to VDS..."
	scp -r infra/host $(VDS_USER)@$(VDS_HOST):/root/cyberlab-setup/
	@echo "Scripts deployed. SSH to VDS and run:"
	@echo "  cd /root/cyberlab-setup/host"
	@echo "  chmod +x *.sh"
	@echo "  ./01-initial-setup.sh"

deploy-labvm:
	@echo "Deploying Lab VM scripts..."
	@echo "Note: Run this after Lab VM is created and accessible"
	@echo "Usage: make deploy-labvm LABVM_IP=192.168.122.x"
ifdef LABVM_IP
	scp -r infra/labvm scenarios scripts Makefile $(VDS_USER)@$(LABVM_IP):/opt/cyberlab/
else
	@echo "Error: LABVM_IP not set. Example: make deploy-labvm LABVM_IP=192.168.122.100"
endif
