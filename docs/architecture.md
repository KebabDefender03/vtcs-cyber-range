# VTCS Cyber Range - Architecture Documentation

## Overview

The VTCS Cyber Range is a containerized red/blue team training environment designed for educational purposes. It provides isolated workspaces for security training exercises while maintaining strong containment and segmentation.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────────────────────┬───────────────────────────┘
                                                  │
                                                  │ UDP 51820 (WireGuard)
                                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CONTABO VDS HOST                                     │
│                        (Ubuntu 24.04 LTS)                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  HOST SERVICES                                                          ││
│  │  • WireGuard VPN Server (10.200.0.1)                                    ││
│  │  • SSH (VPN-only, port 22)                                              ││
│  │  • Cockpit (VPN-only, port 9090) - includes monitoring                  ││
│  │  • Portainer (VPN-only, port 9443) - container management               ││
│  │  • Lab control scripts (/opt/cyberlab/scripts/lab.sh)                   ││
│  │  • KVM/libvirt hypervisor                                               ││
│  │  • nftables + iptables firewall                                         ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    │ virbr0 (192.168.122.0/24)              │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         LAB VM (KVM Guest)                              ││
│  │                        Ubuntu 24.04 Server                               ││
│  │                        192.168.122.10                                    ││
│  │  ┌───────────────────────────────────────────────────────────────────┐  ││
│  │  │                      DOCKER ENGINE                                │  ││
│  │  │                                                                   │  ││
│  │  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │  ││
│  │  │   │  BLUE_NET   │  │  RED_NET    │  │     SERVICES_NET        │  │  ││
│  │  │   │ 172.20.1.0  │  │ 172.20.2.0  │  │      172.20.3.0         │  │  ││
│  │  │   │             │  │             │  │                         │  │  ││
│  │  │   │ ┌─────────┐ │  │ ┌─────────┐ │  │  ┌────────┐ ┌────────┐  │  │  ││
│  │  │   │ │  Blue1  │ │  │ │  Red1   │ │  │  │ WebApp │ │Database│  │  │  ││
│  │  │   │ ├─────────┤ │  │ ├─────────┤ │  │  └────────┘ └────────┘  │  │  ││
│  │  │   │ │  Blue2  │ │  │ │  Red2   │ │  │  ┌─────────────────┐    │  │  ││
│  │  │   │ ├─────────┤ │  │ ├─────────┤ │  │  │   Workstation   │    │  │  ││
│  │  │   │ │  Blue3  │ │  │ │  Red3   │ │  │  └─────────────────┘    │  │  ││
│  │  │   │ └─────────┘ │  │ └─────────┘ │  │                         │  │  ││
│  │  │   └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘  │  ││
│  │  │          │                │                      │               │  ││
│  │  │          └────────────────┴──────────────────────┘               │  ││
│  │  │                    (Services accessible to both teams)           │  ││
│  │  └───────────────────────────────────────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

## Network Architecture

### VPN Network (10.200.0.0/24)
- **Purpose**: Sole entry point from internet
- **Server**: 10.200.0.1 (VDS host)
- **Clients**: 10.200.0.10+ (admin), 10.200.0.100+ (students)
- **Allowed destinations**: Host services, Lab VM network

### Host Network (192.168.122.0/24)
- **Purpose**: libvirt default NAT network
- **Gateway**: 192.168.122.1 (host)
- **Lab VM**: 192.168.122.10 (static)
- **Routing**: VPN clients can reach this network

### Docker Networks (Lab VM internal)

| Network | Subnet | Gateway | Containers |
|---------|--------|---------|------------|
| blue_net | 172.20.1.0/24 | 172.20.1.1 | blue1, blue2, blue3 |
| red_net | 172.20.2.0/24 | 172.20.2.1 | red1, red2, red3 |
| services_net | 172.20.3.0/24 | 172.20.3.1 | webapp, database, workstation |
| bridge | 172.17.0.0/16 | 172.17.0.1 | portainer_agent |

> 💡 Container IPs are assigned dynamically by Docker. Use container names for communication (e.g., `ping webapp`).

### Phase-Based Traffic Control

The lab operates in two phases controlled by the instructor:

| Phase | Internet Access | Cross-Team (Red ↔ Blue) | Duration |
|-------|-----------------|-------------------------|----------|
| **Preparation** | ✅ ENABLED | ❌ BLOCKED | First ~30 min |
| **Combat** | ❌ DISABLED | ✅ ENABLED | Rest of session |

**Phase commands (run on VDS as admin or instructor):**
```bash
sudo /opt/cyberlab/scripts/lab.sh prep      # Enable preparation phase
sudo /opt/cyberlab/scripts/lab.sh combat    # Enable combat phase
sudo /opt/cyberlab/scripts/lab.sh phase     # Check current phase
```

> 💡 Phase control runs on VDS and executes via SSH to Lab VM. Container management (start/stop) is done via Portainer (https://10.200.0.1:9443).

### Traffic Flow Matrix

| From → To | Internet | VPN | Host | Lab VM | Blue | Red | Services |
|-----------|----------|-----|------|--------|------|-----|----------|
| Internet | - | ✓ WG | ✗ | ✗ | ✗ | ✗ | ✗ |
| VPN | ✗ | - | ✓ | ✓ | Via LVM | Via LVM | Via LVM |
| Host | ✓ | ✓ | - | ✓ | Via LVM | Via LVM | Via LVM |
| Lab VM | Controlled | ✓ | ✓ | - | ✓ | ✓ | ✓ |
| Blue | Phase-based | ✗ | ✗ | ✗ | ✓ | Phase-based | ✓ |
| Red | Phase-based | ✗ | ✗ | ✗ | Phase-based | ✓ | ✓ |
| Services | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ |

## Component Details

### Host Layer

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 24.04 LTS | Host operating system |
| WireGuard | Latest | VPN server |
| nftables | Latest | Host firewall |
| iptables | Latest | Additional firewall (Lab VM isolation) |
| KVM/QEMU | Latest | Virtualization |
| libvirt | Latest | VM management |
| Cockpit | Latest | Web-based VM management |
| Portainer | CE 2.x | Docker container management |
| Docker | Latest | For Portainer only |

### Lab VM Layer

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 24.04 LTS | Guest operating system |
| Docker | Latest | Container runtime |
| Docker Compose | v2 | Container orchestration |
| Portainer Agent | Latest | Remote management from VDS |
| nftables | Latest | VM firewall |

> ⚠️ **Security Note**: Lab VM is considered "expendable" - all control scripts run on VDS.
> If Lab VM is compromised via container escape, it cannot affect VDS control plane.


## Monitoring

Monitoring is provided via **Cockpit** - a simple, built-in web console that requires no additional services.

### Cockpit Features
| Feature | Description |
|---------|-------------|
| System Overview | CPU, memory, disk, network graphs |
| Virtual Machines | VM status, console access, resource usage |
| Storage | Disk management and usage |
| Networking | Interface status and configuration |
| Services | systemd service management |
| Logs | journalctl log viewer |

### Access
| Service | URL | Credentials |
|---------|-----|-------------|
| Cockpit | https://10.200.0.1:9090 | Any admin account (admin1/2/3) |

**Why Cockpit instead of Grafana/Prometheus?**
- ✅ Already installed - no additional services
- ✅ VPN-only access - secure by default  
- ✅ VM console access - manage Lab VM directly
- ✅ No privileged containers needed
- ✅ Simpler to maintain

### Container Layer

| Container | Base Image | Resources | Networks | Notes |
|-----------|------------|-----------|----------|-------|
| blue1-3 | Kali Linux | 0.5 CPU, 2GB RAM | blue_net only | Services access via L3 routing |
| red1-3 | Kali Linux | 0.5 CPU, 2GB RAM | red_net only | Services access via L3 routing |
| workstation | Ubuntu 22.04 | 0.3 CPU, 1GB RAM | services_net | Generates realistic background activity |
| webapp | DVWA | 0.5 CPU, 1GB RAM | services_net | Vulnerable application |
| database | MySQL 5.7 | 0.5 CPU, 1GB RAM | services_net | Backend database |
| portainer_agent | Portainer Agent | Minimal | bridge (172.17.0.0/16) | Remote management |

**Total: 10 containers** (6 workspaces + workstation + webapp + database + agent)

> 🔒 **Security Note**: Student containers (blue1-3, red1-3) are **NOT** on services_net.
> This prevents Layer 2 cross-team communication. Access to services (webapp, database, workstation)
> is controlled via iptables routing rules in lab.sh, allowing L3 filtering between teams even in prep mode.

**Workstation Activity**: The workstation container runs continuous background activity that:
- Every 10-30 seconds performs one random action
- Generates HTTP traffic to webapp (normal browsing, logins, vulnerable page access)
- Executes database queries
- Creates realistic application logs

This traffic is visible to blue team via network packet capture (tcpdump) from their blue containers.

## Data Flow

### Student Access Path

```
Student Device
    │
    ▼ WireGuard tunnel (encrypted)
VDS Host (10.200.0.1)
    │
    ▼ Routed via virbr0
Lab VM (192.168.122.x)
    │
    ▼ SSH to container
Workspace Container (172.20.x.x)
```

### Attack Path (Red Team → Target)

```
Red Workspace (172.20.2.x)
    │
    ▼ services_net (172.20.3.0/24)
WebApp (172.20.3.x:80)
    │
    ▼ Internal connection
Database (172.20.3.y:3306)
```

### Monitoring Path (Blue Team)

```
Blue Workspace (172.20.1.x)
    │
    ▼ services_net access
WebApp logs / Database queries
    │
    ▼ Analysis tools (tcpdump, etc.)
Incident detection
```

## Resource Allocation

Total VDS resources: 3 CPU cores, 24 GB RAM

| Component | CPU | RAM | Notes |
|-----------|-----|-----|-------|
| Host OS | 0.5 | 2 GB | Base overhead |
| WireGuard/Firewall | 0.1 | 128 MB | Minimal |
| Cockpit | 0.1 | 256 MB | When active |
| Lab VM overhead | 0.3 | 2 GB | KVM/QEMU |
| 6 Workspaces | 3.0 | 12 GB | 0.5 CPU, 2GB each |
| Workstation | 0.3 | 1 GB | Ubuntu 22.04 |
| WebApp | 0.5 | 1 GB | DVWA |
| Database | 0.5 | 1 GB | MySQL |
| **Total** | ~5.3 | ~19.4 GB | Within limits |

Note: CPU is overcommitted but acceptable for burst workloads.

## Isolation Mechanisms

1. **Network Layer**: Docker bridge networks provide L2 isolation
2. **Firewall Layer**: nftables on host and Lab VM
3. **Container Layer**: Resource limits (cgroups), namespaces
4. **VM Layer**: Full hardware virtualization via KVM
5. **VPN Layer**: Encrypted tunnel, peer authentication

## Recovery Procedures

### Level 1: Container Reset
```bash
# Reset specific workspace
docker restart blue1

# Reset all workspaces but keep data
docker compose restart

# Reset everything including data
docker compose down -v && docker compose up -d
```

### Level 2: Lab VM Snapshot
```bash
# Create snapshot (on host)
virsh snapshot-create-as labvm clean-baseline

# Restore snapshot
virsh snapshot-revert labvm clean-baseline
```

### Level 3: Full Rebuild
```bash
# Destroy and recreate Lab VM
virsh destroy labvm
virsh undefine labvm --remove-all-storage
# Re-run VM creation script
```
