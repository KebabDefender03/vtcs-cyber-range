# VTCS Cyber Range - Security Documentation

## Security Model Overview

The VTCS Cyber Range implements a defense-in-depth security model with multiple layers of protection to ensure that lab activities remain contained and do not impact external systems.

### Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VDS HOST (SECURE ZONE)                       │
│  • All control scripts run here                                 │
│  • Portainer UI (9443) - VPN only                               │
│  • Cockpit (9090) - VPN only                                    │
│  • lab.sh controls Lab VM via SSH                               │
│  • iptables blocks Lab VM from VDS services                     │
├─────────────────────────────────────────────────────────────────┤
│                    LAB VM (EXPENDABLE ZONE)                     │
│  • If compromised via container escape, cannot affect VDS       │
│  • Cannot reach VDS ports 22 or 9443                            │
│  • Portainer Agent (9001) - only VDS can reach                  │
│  • All containers run here                                      │
└─────────────────────────────────────────────────────────────────┘
```

> 🔒 **Key Principle**: VDS is the secure control plane. Lab VM is "expendable" - if compromised, restore from snapshot.

## Security Objectives

1. **Containment**: All attack activities stay within the lab environment
2. **Isolation**: Teams cannot interfere with each other's work
3. **Controlled Access**: Only authorized users can access the environment
4. **Accountability**: All access and significant events are logged
5. **Recovery**: Environment can be restored to a known-good state

## Access Control

### Entry Points

| Entry Point | Protocol | Source | Authentication |
|-------------|----------|--------|----------------|
| WireGuard VPN | UDP/51820 | Internet | Pre-shared keys + peer auth |
| SSH (Host) | TCP/22 | VPN only | Per-user SSH keys or password |
| Cockpit | TCP/9090 | VPN only | Username/password |
| Portainer | TCP/9443 | VPN only | Separate Portainer login |
| SSH (Lab VM) | TCP/22 | VPN only | Per-user SSH keys + ForceCommand |

### User Roles

| Role | Access Level | Capabilities |
|------|--------------|--------------|
| Admin | Full | Host SSH, Cockpit, Portainer, Lab VM, all containers |
| Instructor | VDS Limited | VDS SSH (lab.sh + add-student.sh), Cockpit, Portainer |
| Red Team Student | Workspace | Own workspace + services_net targets |
| Blue Team Student | Workspace | Own workspace + services_net monitoring |

### VPN Client Assignment

```
10.200.0.1    - VPN Server (Host)
10.200.0.10   - Admin 1 (can also SSH as root)
10.200.0.11   - Admin 2
10.200.0.12   - Admin 3
10.200.0.20   - Instructor 1
10.200.0.21   - Instructor 2
10.200.0.100  - Student Red1
10.200.0.101  - Student Red2
10.200.0.102  - Student Red3
10.200.0.110  - Student Blue1
10.200.0.111  - Student Blue2
10.200.0.112  - Student Blue3
```

> **VPN-to-User Binding**: Each VPN IP is restricted to SSH only as the corresponding user. Admin1 can additionally use root.

## Firewall Rules

### Host Firewall (nftables)

**nftables** (`/etc/nftables.conf`):
```nft
chain input {
    policy drop;
    
    # From internet
    udp dport 51820 accept          # WireGuard
    icmp accept
    
    # From VPN (wg0) - all users can SSH
    iifname "wg0" tcp dport 22 accept                                    # SSH
    
    # Cockpit/Portainer - admins and instructors ONLY (not students)
    iifname "wg0" ip saddr { 10.200.0.10-12 } tcp dport 9090 accept     # Cockpit - admins
    iifname "wg0" ip saddr { 10.200.0.20-21 } tcp dport 9090 accept     # Cockpit - instructors
    iifname "wg0" ip saddr { 10.200.0.10-12 } tcp dport 9443 accept     # Portainer - admins
    iifname "wg0" ip saddr { 10.200.0.20-21 } tcp dport 9443 accept     # Portainer - instructors
    
    # Block Lab VM from VDS management services (defense in depth)
    iifname "virbr0" tcp dport { 22, 9090, 9443 } drop
    iifname "virbr0" accept              # Allow other Lab VM traffic
}
```

> ⚠️ **Security**: 
> - Students cannot access Cockpit (9090) or Portainer (9443) - firewall restricts to admin/instructor IPs
> - Lab VM cannot reach VDS management ports. If Lab VM is compromised, attackers cannot pivot to VDS control plane

### Lab VM Firewall (nftables)

```nft
# Default policies
chain input { policy drop; }
chain forward { policy drop; }
chain output { policy accept; }

# Allowed inbound
- SSH from 192.168.122.0/24 (host network)
- SSH from 10.200.0.0/24 (VPN)
- Docker bridge traffic

# Forwarding
- Docker manages inter-container forwarding
- Docker bridges allowed
```

### Docker Network Isolation

Docker networks provide Layer 2 isolation:
- Containers only see traffic on their attached networks
- Routing between blue_net and red_net is controlled by phase
- services_net is shared for controlled target access

## Egress Control & Phase Management

### Phase-Based Access Control

The lab supports two operational phases:

| Phase | Command | Internet | Cross-Team Attacks |
|-------|---------|----------|-------------------|
| **Preparation** | `./scripts/lab.sh prep` | ✅ Enabled | ❌ Blocked |
| **Combat** | `./scripts/lab.sh combat` | ❌ Disabled | ✅ Enabled |

**Check current phase:** `./scripts/lab.sh phase`

### Preparation Phase
- Students can download tools, updates, and packages
- Cross-team attacks are blocked (fair preparation time)
- Typical duration: First 30 minutes of session

### Combat Phase
- Internet access is cut (no external help)
- Cross-team attacks enabled (Red vs Blue!)
- This is the active exercise period

### Technical Implementation

Phase control runs on **VDS Host** and executes via SSH to Lab VM:

```bash
# On VDS as admin or instructor:
sudo /opt/cyberlab/scripts/lab.sh prep     # Enable preparation phase
sudo /opt/cyberlab/scripts/lab.sh combat   # Enable combat phase
sudo /opt/cyberlab/scripts/lab.sh phase    # Check current phase
```

The script uses SSH key `/root/.ssh/portainer_labvm` to execute iptables rules on Lab VM:

```bash
# Preparation Phase (executed on Lab VM via SSH):
iptables -t nat -A POSTROUTING -s 172.20.0.0/16 -o enp1s0 -j MASQUERADE  # Enable NAT
iptables -I FORWARD -s 172.20.2.0/24 -d 172.20.1.0/24 -j DROP          # Block red→blue
iptables -I FORWARD -s 172.20.1.0/24 -d 172.20.2.0/24 -j DROP          # Block blue→red
# Services routing (students NOT on services_net, need L3 routing)
iptables -I FORWARD -s 172.20.2.0/24 -d 172.20.3.0/24 -j ACCEPT        # Red→services
iptables -I FORWARD -s 172.20.1.0/24 -d 172.20.3.0/24 -j ACCEPT        # Blue→services
iptables -I FORWARD -s 172.20.3.0/24 -d 172.20.2.0/24 -j ACCEPT        # Services→red
iptables -I FORWARD -s 172.20.3.0/24 -d 172.20.1.0/24 -j ACCEPT        # Services→blue

# Combat Phase (executed on Lab VM via SSH):
iptables -I FORWARD -s 172.20.0.0/16 ! -d 172.20.0.0/16 -o enp1s0 -j DROP # Block internet
iptables -I FORWARD -s 172.20.2.0/24 -d 172.20.1.0/24 -j ACCEPT        # Allow red→blue
iptables -I FORWARD -s 172.20.1.0/24 -d 172.20.2.0/24 -j ACCEPT        # Allow blue→red
# Services routing (same as prep - students need access to targets)
iptables -I FORWARD -s 172.20.2.0/24 -d 172.20.3.0/24 -j ACCEPT        # Red→services
iptables -I FORWARD -s 172.20.1.0/24 -d 172.20.3.0/24 -j ACCEPT        # Blue→services
iptables -I FORWARD -s 172.20.3.0/24 -d 172.20.2.0/24 -j ACCEPT        # Services→red
iptables -I FORWARD -s 172.20.3.0/24 -d 172.20.1.0/24 -j ACCEPT        # Services→blue
```

> 🔒 **Security**: 
> - Phase control runs on VDS, so even if Lab VM is compromised, attackers cannot modify the control scripts.
> - Student containers are NOT on services_net (L2 isolation) - prevents cross-team communication via shared network.
> - Access to services is controlled via L3 iptables routing, allowing filtering even in prep mode.

## Secrets Management

### Secrets NOT in Git

The following are excluded via `.gitignore`:
- `.env` files (database passwords, etc.)
- WireGuard private keys
- SSH private keys
- TLS certificates

### Secrets Storage

| Secret Type | Location | Protection |
|-------------|----------|------------|
| WireGuard keys | `/etc/wireguard/` | chmod 600, root only |
| Database passwords | `.env` file | Not in git, chmod 600 |
| SSH keys | `~/.ssh/` | Standard SSH permissions |

### Secrets Rotation

1. **VPN Keys**: Regenerate per semester or upon suspected compromise
2. **Passwords**: Reset with each lab reset
3. **SSH Keys**: Rotate for admins annually

## Logging and Monitoring

### Monitoring Architecture (Security Design)

**Approach**: Use Cockpit's built-in monitoring + Portainer for container management.

**Why Cockpit + Portainer?**
- No additional monitoring services to secure/patch
- Portainer runs on VDS (not exposed to Lab VM)
- Agent-only connection (Lab VM cannot reach Portainer UI)
- Already VPN-only by design
- VM console access included in Cockpit
- Sufficient for training environment

**Cockpit provides:**
- CPU, memory, disk, network metrics
- VM management, snapshots, and console
- Service status monitoring
- Log viewing (journalctl)

**Portainer provides:**
- Container start/stop/restart
- Container logs and exec
- Network and volume inspection
- Accessible to instructors without Lab VM SSH

### Host-Level Logging

| Log | Location | Contents |
|-----|----------|----------|
| WireGuard | `journalctl -u wg-quick@wg0` | VPN connections |
| SSH | `/var/log/auth.log` | Authentication attempts |
| Firewall | `journalctl -k` | Dropped packets (with nft log) |
| System | `/var/log/syslog` | General events |
| Cockpit | `journalctl -u cockpit` | Web console access |

### Lab VM Logging

| Log | Location | Contents |
|-----|----------|----------|
| Docker | `journalctl -u docker` | Container lifecycle |
| Container logs | `docker logs <name>` | Application output |
| SSH | `/var/log/auth.log` | Authentication |

### Log Retention

- Host logs: 4 weeks (logrotate)
- Container logs: 10MB per container, 3 files max

### Security Note on Logging

**Lab VM logs are NOT tamper-proof.** If a container escape occurs, an attacker could:
- Delete or modify logs on Lab VM
- Hide their tracks before detection

**Mitigation options (not yet implemented):**
1. **Syslog forwarding to VDS** - Logs stream in real-time, survive Lab VM compromise
2. **VM snapshots** - Restore to known-good state after incidents
3. **Accept risk** - For training purposes, reset environment if compromised

Current approach: Logs on Lab VM + regular snapshots. Admins can investigate via VDS Cockpit.

## Incident Response

### Suspected Compromise

1. **Isolate**: Disconnect VDS from internet (Contabo console)
2. **Preserve**: Snapshot VMs before investigation
3. **Investigate**: Review logs for indicators
4. **Recover**: Restore from known-good snapshot
5. **Report**: Document incident for learning

### Emergency Reset

```bash
# Reset containers via Portainer (https://10.200.0.1:9443)
# Or restore Lab VM snapshot via Cockpit/virsh
virsh snapshot-revert labvm clean-baseline
```

## Security Hardening Checklist

### Host Hardening
- [x] Root SSH restricted to key-only (admin1 key also authorized for emergency)
- [x] SSH key-only authentication (PasswordAuthentication no)
- [x] Automatic security updates (unattended-upgrades)
- [x] fail2ban for SSH protection
- [x] nftables firewall with default deny
- [x] WireGuard as sole entry point

### Lab VM Hardening
- [x] Non-root user for Docker operations
- [x] nftables firewall
- [x] Docker daemon configuration (log limits, default network config)
- [x] Resource limits on all containers

### Container Hardening
- [x] Non-root container users where possible
- [x] Resource limits (CPU, memory)
- [x] No privileged containers
- [x] Read-only filesystems where appropriate
- [ ] AppArmor/SELinux profiles (future enhancement)

## Known Limitations (POC)

1. **No container escape protection**: Students with sudo in containers could potentially escape
   - Mitigation: Education, monitoring, regular resets
   
2. ~~**Shared credentials**~~: **RESOLVED** - Per-user SSH keys implemented with ForceCommand
   - Each user has unique SSH keypair
   - Students auto-exec into their assigned container

3. **No network traffic encryption between containers**
   - Mitigation: Acceptable for training; attackers can sniff (realistic)

4. ~~**Single admin account**~~: **RESOLVED** - Multiple admin accounts created
   - 3 VDS host admins (admin1, admin2, admin3)
   - 3 Lab VM admins (labadmin1, labadmin2, labadmin3)
   - 2 Instructor accounts with limited privileges

## Security Testing

### Pre-Deployment Checks

```bash
# Test firewall rules
nmap -Pn -p 1-1000 <VDS_IP>  # Only 51820 should be open

# Test VPN isolation
# Without VPN:
ssh root@<VDS_IP>  # Should timeout

# With VPN:
ssh root@10.200.0.1  # Should connect
```

### Container Isolation Tests

```bash
# From red1, try to reach blue1
docker exec red1 ping 172.20.1.x  # Should fail

# From red1, try to reach webapp
docker exec red1 curl http://webapp  # Should work
```

## Compliance Notes

This environment is for **educational purposes only**:
- No real user data
- No production systems
- Isolated from university networks
- Students sign acceptable use agreement

---
**Last Updated:** February 2026
