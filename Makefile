# ============================================================================
# VTCS Cyber Range - Makefile
# ============================================================================
# Convenience targets for deployment
# Container management: Portainer (https://10.200.0.1:9443)
# Phase control: lab.sh on VDS host
# ============================================================================

.PHONY: help prep combat phase deploy-host deploy-labvm

# Default target
help:
	@echo "VTCS Cyber Range - Available Targets"
	@echo "====================================="
	@echo ""
	@echo "Phase Control (run on VDS as admin/instructor):"
	@echo "  sudo /opt/cyberlab/scripts/lab.sh prep    - Preparation phase"
	@echo "  sudo /opt/cyberlab/scripts/lab.sh combat  - Combat phase"
	@echo "  sudo /opt/cyberlab/scripts/lab.sh phase   - Check current phase"
	@echo ""
	@echo "Container Management:"
	@echo "  Portainer: https://10.200.0.1:9443"
	@echo ""
	@echo "VM Snapshots:"
	@echo "  Cockpit: https://10.200.0.1:9090"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-host    - Deploy host setup scripts to VDS"
	@echo "  make deploy-labvm   - Deploy lab VM scripts"
	@echo ""
	@echo ""

# Configuration
SCENARIO ?= base
SCRIPTS_DIR := scripts
SCENARIOS_DIR := scenarios

# Phase control targets (run on VDS as admin/instructor)
prep:
	@echo "Run on VDS: sudo /opt/cyberlab/scripts/lab.sh prep"

combat:
	@echo "Run on VDS: sudo /opt/cyberlab/scripts/lab.sh combat"

phase:
	@echo "Run on VDS: sudo /opt/cyberlab/scripts/lab.sh phase"

# Container management: Use Portainer (https://10.200.0.1:9443)
# VM snapshots: Use Cockpit (https://10.200.0.1:9090)

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
