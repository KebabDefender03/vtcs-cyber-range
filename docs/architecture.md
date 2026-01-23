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
│  │  • KVM/libvirt hypervisor                                               ││
│  │  • nftables firewall                                                    ││
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

| Network | Subnet | Purpose | Containers |
|---------|--------|---------|------------|
| blue_net | 172.20.1.0/24 | Blue team internal | Blue1, Blue2, Blue3 |
| red_net | 172.20.2.0/24 | Red team internal | Red1, Red2, Red3 |
| services_net | 172.20.3.0/24 | Shared targets | WebApp, Database, Workstation, All workspaces |

### Phase-Based Traffic Control

The lab operates in two phases controlled by the instructor:

| Phase | Internet Access | Cross-Team (Red ↔ Blue) | Duration |
|-------|-----------------|-------------------------|----------|
| **Preparation** | ✅ ENABLED | ❌ BLOCKED | First ~30 min |
| **Combat** | ❌ DISABLED | ✅ ENABLED | Rest of session |

**Phase commands:**
```bash
./scripts/lab.sh prep      # Enable preparation phase
./scripts/lab.sh combat    # Enable combat phase
./scripts/lab.sh phase     # Check current phase
```

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
| KVM/QEMU | Latest | Virtualization |
| libvirt | Latest | VM management |
| Cockpit | Latest | Web-based VM management |

### Lab VM Layer

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 24.04 LTS | Guest operating system |
| Docker | Latest | Container runtime |
| Docker Compose | v2 | Container orchestration |
| nftables | Latest | VM firewall |


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

| Container | Base Image | Resources | Networks |
|-----------|------------|-----------|----------|
| blue1-3 | Kali Linux | 0.5 CPU, 2GB RAM | blue_net, services_net |
| red1-3 | Kali Linux | 0.5 CPU, 2GB RAM | red_net, services_net |
| workstation | Ubuntu 22.04 | 0.3 CPU, 1GB RAM | services_net |
| webapp | DVWA | 0.5 CPU, 1GB RAM | services_net |
| database | MySQL 5.7 | 0.5 CPU, 1GB RAM | services_net |

**Total: 9 containers** (6 workspaces + workstation + webapp + database)

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
