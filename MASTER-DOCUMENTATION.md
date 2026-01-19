# Cyber Security Training Environment - Master Documentation

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                     │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │
                     ┌─────────────▼─────────────┐
                     │   VDS Host (Contabo)      │
                     │   62.171.146.215          │
                     │   Ubuntu 24.04 LTS        │
                     │                           │
                     │   ┌───────────────────┐   │
                     │   │ WireGuard VPN     │   │
                     │   │ 10.200.0.1/24     │   │
                     │   │ Port 51820/UDP    │   │
                     │   └───────────────────┘   │
                     │   ┌───────────────────┐   │
                     │   │ Cockpit GUI       │   │
                     │   │ Port 9090 (VPN)   │   │
                     │   └───────────────────┘   │
                     │   ┌───────────────────┐   │
                     │   │ nftables Firewall │   │
                     │   └───────────────────┘   │
                     │   ┌───────────────────┐   │
                     │   │ KVM/libvirt       │   │
                     │   └─────────┬─────────┘   │
                     └─────────────┼─────────────┘
                                   │ virbr0 (192.168.122.0/24)
                     ┌─────────────▼─────────────┐
                     │   Lab VM (192.168.122.10) │
                     │   Ubuntu + Docker         │
                     │                           │
                     │  ┌────────────────────────────────────────────┐
                     │  │           SEGMENTED DOCKER NETWORKS        │
                     │  │                                            │
                     │  │  ┌──────────────┐    ┌──────────────┐      │
                     │  │  │   RED_NET    │    │   BLUE_NET   │      │
                     │  │  │ 172.20.2.0/24│    │ 172.20.1.0/24│      │
                     │  │  │              │    │              │      │
                     │  │  │ ┌────┐┌────┐ │    │ ┌────┐┌────┐ │      │
                     │  │  │ │red1││red2│ │    │ │blue││blue│ │      │
                     │  │  │ └────┘└────┘ │    │ │ 1  ││ 2  │ │      │
                     │  │  │    ┌────┐    │    │ └────┘└────┘ │      │
                     │  │  │    │red3│    │    │    ┌────┐    │      │
                     │  │  │    └────┘    │    │    │blue│    │      │
                     │  │  │      │       │    │    │ 3  │    │      │
                     │  │  └──────┼───────┘    └────┼────┘    │      │
                     │  │         │                 │          │      │
                     │  │         └────────┬────────┘          │      │
                     │  │                  │                   │      │
                     │  │         ┌────────▼────────┐          │      │
                     │  │         │  SERVICES_NET   │          │      │
                     │  │         │  172.20.3.0/24  │          │      │
                     │  │         │                 │          │      │
                     │  │         │ ┌──────┐┌─────┐ │          │      │
                     │  │         │ │webapp││ db  │ │          │      │
                     │  │         │ │(DVWA)││MySQL│ │          │      │
                     │  │         │ └──────┘└─────┘ │          │      │
                     │  │         │ ┌────────────┐ │          │      │
                     │  │         │ │workstation │ │          │      │
                     │  │         │ └────────────┘ │          │      │
                     │  │         └─────────────────┘          │      │
                     │  └────────────────────────────────────────────┘
                     └───────────────────────────────────────────┘
```

## Network Segmentation

### Why Segmentation Matters
- **Red team cannot attack Blue team directly** - Only through shared services
- **Blue team cannot see Red team traffic** - Prevents cheating
- **Both teams share targets** - Realistic attack/defend scenario

### Docker Network Isolation

| Network | Subnet | Containers | Can Reach |
|---------|--------|------------|-----------|
| `red_net` | 172.20.2.0/24 | red1, red2, red3 | services_net only |
| `blue_net` | 172.20.1.0/24 | blue1, blue2, blue3 | services_net only |
| `services_net` | 172.20.3.0/24 | webapp, database, workstation | Internal only |

### Traffic Flow
```
Red Team ──────┐
               ├───► services_net (webapp, db)
Blue Team ─────┘
       ✗
Red ←──────→ Blue  (BLOCKED - no direct communication)
```

## Access Matrix

| Role | VDS Host | Lab VM | Docker | Targets |
|------|----------|--------|--------|---------|
| Admin (1-3) | Full sudo | Full sudo | Full control | All |
| Instructor (1-2) | ❌ | Shell + docker | Inspect/restart | Monitor |
| Red Team (1-3) | ❌ | Container only | Own container | webapp, db |
| Blue Team (1-3) | ❌ | Container only | Own container | Monitor traffic |

## User Accounts

### VDS Host Users
| Username | Purpose | SSH Key | Sudo |
|----------|---------|---------|------|
| admin1 | Primary admin | host_admin1.key | Yes |
| admin2 | Backup admin | host_admin2.key | Yes |
| admin3 | Backup admin | host_admin3.key | Yes |
| root | Emergency only | Contabo key | Yes |

### Lab VM Users

> 💡 **Admins can use `ssh labvm` from VDS** - SSH config auto-selects key and username.

| Username | Purpose | SSH Key | ForceCommand |
|----------|---------|---------|--------------|
| labadmin1 | Admin | labvm_admin1.key | No (full shell) |
| labadmin2 | Admin | labvm_admin2.key | No (full shell) |
| labadmin3 | Admin | labvm_admin3.key | No (full shell) |
| instructor1 | Instructor | labvm_instructor1.key | No (shell + docker) |
| instructor2 | Instructor | labvm_instructor2.key | No (shell + docker) |
| red1 | Red Team Student | labvm_red1.key | docker exec -it red1 /bin/bash |
| red2 | Red Team Student | labvm_red2.key | docker exec -it red2 /bin/bash |
| red3 | Red Team Student | labvm_red3.key | docker exec -it red3 /bin/bash |
| blue1 | Blue Team Student | labvm_blue1.key | docker exec -it blue1 /bin/bash |
| blue2 | Blue Team Student | labvm_blue2.key | docker exec -it blue2 /bin/bash |
| blue3 | Blue Team Student | labvm_blue3.key | docker exec -it blue3 /bin/bash |

## VPN Assignments

| Config File | VPN IP | Assigned To |
|-------------|--------|-------------|
| admin.conf | 10.200.0.10 | Admin 1 |
| admin2.conf | 10.200.0.11 | Admin 2 |
| admin3.conf | 10.200.0.12 | Admin 3 |
| instructor1.conf | 10.200.0.20 | Instructor 1 |
| instructor2.conf | 10.200.0.21 | Instructor 2 |
| student-red1.conf | 10.200.0.100 | Red Team 1 |
| student-red2.conf | 10.200.0.101 | Red Team 2 |
| student-red3.conf | 10.200.0.102 | Red Team 3 |
| student-blue1.conf | 10.200.0.110 | Blue Team 1 |
| student-blue2.conf | 10.200.0.111 | Blue Team 2 |
| student-blue3.conf | 10.200.0.112 | Blue Team 3 |

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
- ✅ Resource limits applied (0.5 CPU, 2GB RAM per workspace)
- ✅ Network namespace isolation between teams

## GUI Access Options

### Currently Available
| Interface | URL | Purpose | Security Impact |
|-----------|-----|---------|-----------------|
| **Cockpit** | https://10.200.0.1:9090 | VDS host management, VM console | Low - VPN required |

### Optional GUIs (Not Deployed)

| Option | Purpose | Security Risk | Recommendation |
|--------|---------|---------------|----------------|
| **Portainer** | Docker management GUI | Medium - API access to all containers | Only if needed for instructors |
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
- [ ] Lab VM SSH key (labvm_admin{N}.key)
- [ ] README with credentials and instructions

> **Note**: Admin credentials are in the user-packages READMEs (not stored in this repo for security).

### For Each Instructor:
- [ ] VPN config (instructor1.conf or instructor2.conf)
- [ ] Lab VM SSH key (labvm_instructor1.key or labvm_instructor2.key)
- [ ] README with instructions

### For Each Student:
- [ ] VPN config (student-red1.conf, etc.)
- [ ] Lab VM SSH key (labvm_red1.key, etc.)
- [ ] README with rules and instructions

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

### If Malware Escapes Container:
1. SSH to Lab VM, stop all containers: `docker stop $(docker ps -q)`
2. Check host for compromise
3. If compromised, shutdown VM and restore from backup
4. Contact security team

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
- Check for container escape attempts

## File Locations

### VDS Host:
- WireGuard config: `/etc/wireguard/wg0.conf`
- Firewall rules: `/etc/nftables.conf`
- SSH keys: `/root/.ssh/`
- VM images: `/var/lib/libvirt/images/`

### Lab VM:
- Docker compose: `/home/labadmin/docker-compose.yml`
- Container data: `/home/labadmin/kali-data/`
- User SSH keys: `/home/*/.ssh/authorized_keys`

## Quick Reference Commands

### VDS Host (as admin):
```bash
# Check VPN status
wg show

# List VPN peers
wg show wg0 peers

# Check firewall
nft list ruleset

# VM status
virsh list --all

# Start/stop Lab VM
virsh start labvm
virsh shutdown labvm
```

### Lab VM (as labadmin):
```bash
# Container status
docker ps -a

# View container logs
docker logs -f red1

# Restart all containers
docker-compose restart

# Resource usage
docker stats

# Enter container as admin
docker exec -it red1 /bin/bash
```

---
**Document Version:** 1.0
**Last Updated:** $(date)
**Classification:** Internal Use Only
