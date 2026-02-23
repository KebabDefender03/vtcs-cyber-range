# Cyber Security Training Environment - Master Documentation

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                                   INTERNET                                    │
└───────────────────────────────────────┬───────────────────────────────────────┘
                                        │
                                        │ UDP 51820 (WireGuard)
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                               CONTABO VDS HOST                                │
│                               (Ubuntu 24.04 LTS)                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │  HOST SERVICES                                                          │  │
│  │  • WireGuard VPN Server (10.200.0.1)                                    │  │
│  │  • SSH (VPN-only, port 22)                                              │  │
│  │  • Cockpit (VPN-only, port 9090) - includes monitoring                  │  │
│  │  • Portainer (VPN-only, port 9443) - container management               │  │
│  │  • Lab control scripts (/opt/cyberlab/scripts/lab.sh)                   │  │
│  │  • KVM/libvirt hypervisor                                               │  │
│  │  • nftables + iptables firewall                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    │ virbr0 (192.168.122.0/24)                │
│                                    ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         LAB VM (KVM Guest)                              │  │
│  │                         Ubuntu 24.04 Server                             │  │
│  │                         192.168.122.10                                  │  │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      DOCKER ENGINE                                │  │  │
│  │  │                                                                   │  │  │
│  │  │   ┌─────────────┐  ┌─────────────────────────┐  ┌─────────────┐   │  │  │
│  │  │   │  RED_NET    │  │     SERVICES_NET        │  │  BLUE_NET   │   │  │  │
│  │  │   │ 172.20.2.0  │  │      172.20.3.0         │  │ 172.20.1.0  │   │  │  │
│  │  │   │             │  │                         │  │             │   │  │  │
│  │  │   │ ┌─────────┐ │  │  ┌────────┐ ┌────────┐  │  │ ┌─────────┐ │   │  │  │
│  │  │   │ │  Red1   │ │  │  │ WebApp │ │Database│  │  │ │  Blue1  │ │   │  │  │
│  │  │   │ ├─────────┤ │  │  └────────┘ └────────┘  │  │ ├─────────┤ │   │  │  │
│  │  │   │ │  Red2   │ │  │  ┌─────────────────┐    │  │ │  Blue2  │ │   │  │  │
│  │  │   │ ├─────────┤ │  │  │   Workstation   │    │  │ ├─────────┤ │   │  │  │
│  │  │   │ │  Red3   │ │  │  └─────────────────┘    │  │ │  Blue3  │ │   │  │  │
│  │  │   │ └─────────┘ │  │                         │  │ └─────────┘ │   │  │  │
│  │  │   └──────┬──────┘  └────────────┬────────────┘  └──────┬──────┘   │  │  │
│  │  │          │                      │                      │          │  │  │
│  │  │          └──────────────────────┴──────────────────────┘          │  │  │
│  │  │                (Services accessible to both teams)                │  │  │
│  │  └───────────────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        VDS HOST (SECURE ZONE)                          │
│   • All control scripts (/opt/cyberlab/scripts/lab.sh)                 │
│   • Portainer UI (9443) - Web management console                       │
│   • Cockpit (9090) - System administration GUI                         │
│   • WireGuard VPN server                                               │
│   • nftables + iptables firewall rules                                 │
│   • Admin/Instructor accounts with limited sudo                        │
├────────────────────────────────────────────────────────────────────────┤
│                          FIREWALL BOUNDARY                             │
│   • Lab VM blocked from VDS port 22 (SSH)                              │
│   • Lab VM blocked from VDS port 9443 (Portainer)                      │
│   • Only VDS can SSH to Lab VM (/root/.ssh/portainer_labvm key)        │
├────────────────────────────────────────────────────────────────────────┤
│                      LAB VM (EXPENDABLE ZONE)                          │
│   • Docker containers (all 10 lab containers)                          │
│   • Portainer Agent only (port 9001)                                   │
│   • No control scripts - receives commands via SSH from VDS            │
│   • Can be wiped/rebuilt without affecting VDS                         │
└────────────────────────────────────────────────────────────────────────┘
```

**Security Principle**: VDS is the secure control plane. Lab VM is expendable.
- Containers cannot reach VDS management services
- All administrative actions go through VDS (never direct to Lab VM for instructors)
- Phase control runs via: `VDS lab.sh` → SSH → `Lab VM iptables/nftables commands`

## Network Segmentation

### Phase-Based Access Control

The lab operates in two phases to support structured training sessions:

| Phase | Command | Internet | Red ↔ Blue | Purpose |
|-------|---------|----------|------------|---------|
| **Preparation** | `./scripts/lab.sh prep` | ✅ ON | ❌ OFF | Download tools, setup |
| **Combat** | `./scripts/lab.sh combat` | ❌ OFF | ✅ ON | Attack/defend exercise |

Check current phase: `./scripts/lab.sh phase`

### Why Segmentation Matters
- **Preparation phase**: Teams download tools without being attacked
- **Combat phase**: Cross-team attacks enabled, no external help (internet off)
- **Both teams share targets** - Realistic attack/defend scenario

### Docker Network Layout

| Network | Subnet | Containers | Can Reach |
|---------|--------|------------|-----------|
| `red_net` | 172.20.2.0/24 | red1, red2, red3 | services_net + blue_net (combat only) |
| `blue_net` | 172.20.1.0/24 | blue1, blue2, blue3 | services_net + red_net (combat only) |
| `services_net` | 172.20.3.0/24 | webapp, database, workstation | Internal only |

### Traffic Flow
```
PREPARATION PHASE:                      COMBAT PHASE:
                                        
Red Team ──────┐                        Red Team ◄─────► Blue Team
               │                              │              │
               ├───► services_net             └──────┬───────┘
               │                                     │
Blue Team ─────┘                                     ▼
       ✗                                      services_net
Red ←───✗───→ Blue                         (webapp, db, workstation)

Internet: ✅ ON                           Internet: ❌ OFF
```

## Access Matrix

| Role | VDS Host | Lab VM | Docker | Targets |
|------|----------|--------|--------|---------|
| Admin (1-3) | Full sudo | Full sudo | Full control | All |
| Instructor (1-2) | SSH + lab.sh + Cockpit + Portainer | SSH via VDS | Via Portainer | Monitor |
| Red Team (1-3) | SSH (ForceCommand) | Via ForceCommand | Own container only | webapp, db |
| Blue Team (1-3) | SSH (ForceCommand) | Via ForceCommand | Own container only | Monitor traffic |

## User Accounts

### VDS Host Users
| Username | Purpose | SSH Key | Sudo |
|----------|---------|---------|------|
| admin1 | Primary admin | host_admin1.key | Full |
| admin2 | Backup admin | host_admin2.key | Full |
| admin3 | Backup admin | host_admin3.key | Full |
| instructor1 | Lab instructor | host_instructor1.key | lab.sh + add-student.sh |
| instructor2 | Lab instructor | host_instructor2.key | lab.sh + add-student.sh |
| red1 | Red Team Student | red1.key | None (ForceCommand) |
| red2 | Red Team Student | red2.key | None (ForceCommand) |
| red3 | Red Team Student | red3.key | None (ForceCommand) |
| blue1 | Blue Team Student | blue1.key | None (ForceCommand) |
| blue2 | Blue Team Student | blue2.key | None (ForceCommand) |
| blue3 | Blue Team Student | blue3.key | None (ForceCommand) |
| root | Emergency only | Contabo key | Full |

> **Student Access Flow**: Students SSH to VDS → ForceCommand executes `ssh labvm docker exec -it <container> bash` → Student lands directly in their Kali container.

### Lab VM Users

> 💡 **Admins can use `ssh labvm` from VDS** - SSH config auto-selects key and username.
> ⚠️ **Students SSH to VDS** - ForceCommand automatically connects them to their container.

| Username | Purpose | SSH Key | Notes |
|----------|---------|---------|-------|
| labadmin1 | Admin | Via VDS ~/.ssh/ | Full shell access |
| labadmin2 | Admin | Via VDS ~/.ssh/ | Full shell access |
| labadmin3 | Admin | Via VDS ~/.ssh/ | Full shell access |
| instructor1 | Instructor | Via VDS ~/.ssh/ | Full shell access |
| instructor2 | Instructor | Via VDS ~/.ssh/ | Full shell access |

> **Note**: Student users (red1-3, blue1-3) no longer exist on Lab VM. Students SSH to VDS where ForceCommand runs `ssh labvm docker exec -it <container> bash`.

## VPN Assignments

| Config File | VPN IP | Assigned To |
|-------------|--------|-------------|
| admin.conf | 10.200.0.10 | Admin 1 |
| admin2.conf | 10.200.0.11 | Admin 2 |
| admin3.conf | 10.200.0.12 | Admin 3 |
| instructor1.conf | 10.200.0.20 | Instructor 1 |
| instructor2.conf | 10.200.0.21 | Instructor 2 |
| red1.conf | 10.200.0.100 | Red Team 1 |
| red2.conf | 10.200.0.101 | Red Team 2 |
| red3.conf | 10.200.0.102 | Red Team 3 |
| blue1.conf | 10.200.0.110 | Blue Team 1 |
| blue2.conf | 10.200.0.111 | Blue Team 2 |
| blue3.conf | 10.200.0.112 | Blue Team 3 |

> **Reserved ranges**: 10.200.0.10-19 for admins, 10.200.0.20-29 for instructors

## Security Measures

### Network Security
- ✅ All access requires WireGuard VPN connection
- ✅ nftables firewall blocks non-VPN traffic
- ✅ Internal network isolated from internet
- ✅ **Red/Blue team networks fully segmented** (cannot attack each other)
- ✅ Shared services network for legitimate targets only

### Authentication Security
- ✅ SSH key-only authentication (password auth disabled)
- ✅ Unique SSH key per user
- ✅ SSH config on VDS enables `ssh labvm` shortcut for admins
- ✅ ForceCommand restricts students to containers
- ✅ No port/X11/agent forwarding for students
- ✅ VPN IPs whitelisted in fail2ban (won't lock out admins)

### Container Isolation
- ✅ Each student has dedicated container
- ✅ Containers cannot access host filesystem
- ✅ Docker socket not exposed to students
- ✅ Resource limits applied (0.4 CPU, 2GB RAM per workspace)
- ✅ Network namespace isolation between teams

## GUI Access Options

### Currently Available
| Interface | URL | Purpose | Security Impact |
|-----------|-----|---------|-----------------|
| **Cockpit** | https://10.200.0.1:9090 | VDS host management, VM console, snapshots | Low - VPN required |
| **Portainer** | https://10.200.0.1:9443 | Docker container management via agent | Low - VPN required, agent-only |

> 💡 **Portainer runs on VDS** and connects to Lab VM via agent on port 9001. Lab VM cannot reach Portainer UI.

### Optional GUIs (Not Deployed)

| Option | Purpose | Security Risk | Recommendation |
|--------|---------|---------------|----------------|
| **VNC to Lab VM** | Desktop access to Lab VM | High - additional attack surface | Avoid unless essential |
| **noVNC** | Browser-based VNC | High - web service exposure | Not recommended |

### Why Minimal GUIs?
Each GUI adds:
1. **Additional services** to patch and maintain
2. **Authentication mechanisms** that could be bypassed
3. **Network ports** that increase attack surface
4. **Potential privilege escalation** paths

**Current approach**: CLI-based management via SSH + Cockpit for VM console only.

## Distribution Checklist

### For Each Admin (1, 2 & 3):
- [ ] VPN config (in user-packages/admin{N}/ folder)
- [ ] Host SSH key (host_admin{N}.key)
- [ ] README with credentials and instructions

> **Note**: Admin Lab VM keys are stored on VDS in `~/.ssh/` - use `ssh labvm` from VDS.

### For Each Instructor:
- [ ] VPN config (instructor1.conf or instructor2.conf)
- [ ] Host SSH key (host_instructor{N}.key)
- [ ] README with instructions

> **Note**: Instructors access Lab VM via Portainer/Cockpit, not SSH.

### For Each Student:
- [ ] VPN config (student-red1.conf, etc.)
- [ ] VDS SSH key (red1.key, etc.) - connects to VDS, ForceCommand handles container access
- [ ] README with rules and instructions

> **Note**: Students SSH to VDS (10.200.0.1). ForceCommand automatically executes `ssh labvm docker exec -it <container> bash`.

## Emergency Procedures

### If Locked Out of VDS Host:
1. Use Contabo VNC console
2. Login as root with Contabo password
3. Fix SSH config or authorized_keys

### If Locked Out of Lab VM:
1. SSH to VDS host as admin
2. Stop Lab VM: `virsh shutdown labvm`
3. Mount disk: `guestmount -a /var/lib/libvirt/images/labvm.qcow2 -m /dev/sda1 /mnt`
4. Fix /mnt/home/*/. ssh/authorized_keys
5. Unmount: `guestunmount /mnt`
6. Start VM: `virsh start labvm`

### If Student Misbehaves:
1. SSH to Lab VM as admin
2. Stop their container: `docker stop red1`
3. Check logs: `docker logs red1`
4. Optionally remove them from authorized_keys

### If Lab VM Needs Reset:
1. Restore from snapshot via Cockpit
2. Redeploy stack via Portainer

## Maintenance Tasks

### Weekly:
- Check container logs for suspicious activity
- Verify all services running
- Check disk space

### Before Each Session:
- Restart all student containers (fresh state)
- Verify DVWA and database accessible
- Test one student connection

### After Each Session:
- Review logs
- Reset DVWA database if needed

## File Locations

### VDS Host:
- WireGuard config: `/etc/wireguard/wg0.conf`
- Firewall rules: `/etc/nftables.conf` + `/etc/iptables/rules.v4`
- Lab control script: `/opt/cyberlab/scripts/lab.sh`
- Student onboarding: `/opt/cyberlab/scripts/add-student.sh`
- Student packages: `/opt/cyberlab/student-packages/`
- Lab VM SSH key (root): `/root/.ssh/portainer_labvm`
- Shared Lab VM key: `/etc/cyberlab/keys/labvm_key` (for ForceCommand)
- Global SSH config: `/etc/ssh/ssh_config.d/labvm.conf` (labvm alias)
- VPN client configs: `/opt/cyberlab/vpn-configs/`
- Instructor sudoers: `/etc/sudoers.d/instructors`
- VM images: `/var/lib/libvirt/images/`
- Portainer data: `/var/lib/docker/volumes/portainer_data/`

### Lab VM:
- Portainer agent: Running on port 9001 (container management)
- Docker containers: Deployed via Portainer from GitHub
- User SSH keys: `/home/{labadmin1,labadmin2,labadmin3,instructor1,instructor2}/.ssh/authorized_keys`

> **Note**: Docker Compose files are no longer stored locally. Portainer deploys the "vtcs" stack directly from GitHub repository.

## Quick Reference Commands

### VDS Host (as admin):
```bash
# Phase control
sudo /opt/cyberlab/scripts/lab.sh prep      # Internet ON, cross-team OFF
sudo /opt/cyberlab/scripts/lab.sh combat    # Internet OFF, cross-team ON
sudo /opt/cyberlab/scripts/lab.sh phase     # Check current phase

# Container management: Use Portainer (https://10.200.0.1:9443)

# Check VPN status
sudo wg show

# Check firewall
sudo nft list ruleset
sudo iptables -L -n

# VM management
virsh list --all
virsh start labvm
virsh shutdown labvm
virsh snapshot-list labvm
```

### Web Interfaces (VPN required):
- **Cockpit**: https://10.200.0.1:9090 (VM management, snapshots)
- **Portainer**: https://10.200.0.1:9443 (container management)

### Lab VM (as labadmin via `ssh labvm`):
```bash
# Container status
docker ps -a

# View container logs
docker logs -f red1

# Resource usage
docker stats

# Enter container as admin
docker exec -it red1 /bin/bash
```

> **Note**: Container start/stop/restart is managed via Portainer (https://10.200.0.1:9443).

---
**Document Version:** 1.2
**Last Updated:** February 2026
**Classification:** Internal Use Only
