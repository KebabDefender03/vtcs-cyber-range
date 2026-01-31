#!/bin/bash
# ============================================================================
# VTCS Cyber Range POC - Lab VM Creation
# ============================================================================
# Creates the Ubuntu Lab VM using libvirt/KVM.
# This VM will host Docker and all lab containers.
#
# Resources: 2 vCPUs, 16GB RAM (leaves 8GB for host + overhead)
# Storage: 80GB qcow2 disk
# Network: NAT via virbr0 (192.168.122.x)
# ============================================================================

set -euo pipefail

# Configuration
VM_NAME="labvm"
VM_RAM="16384"      # 16GB in MB
VM_VCPUS="2"
VM_DISK_SIZE="80"   # GB
VM_DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso"
UBUNTU_ISO_PATH="/var/lib/libvirt/images/ubuntu-24.04-server.iso"

echo "=========================================="
echo "VTCS Cyber Range - Lab VM Creation"
echo "=========================================="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" 
   exit 1
fi

# Check if VM already exists
if virsh dominfo ${VM_NAME} &>/dev/null; then
    echo "VM '${VM_NAME}' already exists."
    echo "To recreate, first run: virsh destroy ${VM_NAME}; virsh undefine ${VM_NAME} --remove-all-storage"
    exit 1
fi

# Download Ubuntu ISO if not present
echo "[1/4] Checking Ubuntu ISO..."
if [[ ! -f "${UBUNTU_ISO_PATH}" ]]; then
    echo "  Downloading Ubuntu Server ISO..."
    wget -O "${UBUNTU_ISO_PATH}" "${UBUNTU_ISO_URL}"
else
    echo "  ISO already exists at ${UBUNTU_ISO_PATH}"
fi

# Create disk image
echo "[2/4] Creating disk image (${VM_DISK_SIZE}GB)..."
qemu-img create -f qcow2 "${VM_DISK_PATH}" ${VM_DISK_SIZE}G

# Create the VM
echo "[3/4] Creating VM definition..."
virt-install \
    --name ${VM_NAME} \
    --ram ${VM_RAM} \
    --vcpus ${VM_VCPUS} \
    --disk path=${VM_DISK_PATH},format=qcow2 \
    --cdrom ${UBUNTU_ISO_PATH} \
    --os-variant ubuntu24.04 \
    --network network=default \
    --graphics vnc,listen=127.0.0.1 \
    --noautoconsole \
    --boot uefi

echo "[4/4] VM created and started!"

# Get VNC port
VNC_PORT=$(virsh vncdisplay ${VM_NAME} 2>/dev/null | sed 's/://') || true

echo ""
echo "=========================================="
echo "Lab VM creation complete!"
echo "=========================================="
echo ""
echo "VM Name: ${VM_NAME}"
echo "RAM: ${VM_RAM}MB"
echo "vCPUs: ${VM_VCPUS}"
echo "Disk: ${VM_DISK_PATH}"
echo ""
echo "NEXT STEPS:"
echo "1. Connect to VNC console via Cockpit or:"
echo "   - Via VPN tunnel: vncviewer 10.200.0.1:${VNC_PORT:-0}"
echo ""
echo "2. Complete Ubuntu installation manually"
echo "   - Set hostname: labvm"
echo "   - Create user: labadmin1 (bootstrap script will create additional users)"
echo "   - Install OpenSSH server"
echo "   - Note the IP address assigned (likely 192.168.122.x)"
echo ""
echo "3. After installation, run the bootstrap script on the Lab VM:"
echo "   scp infra/labvm/01-labvm-bootstrap.sh labadmin1@<VM_IP>:~/"
echo "   ssh labadmin1@<VM_IP> 'sudo bash ~/01-labvm-bootstrap.sh'"
echo ""
