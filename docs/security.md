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
│  • Cannot reach VDS management ports (22, 9443)                 │
│  • Portainer Agent (9001) - only VDS can reach                  │
│  • All containers run here                                      │
│  • If issues occur, restore from snapshot                       │
└─────────────────────────────────────────────────────────────────┘
```

> 🔒 **Key Principle**: VDS is the secure control plane. Lab VM is "expendable" - if issues occur, restore from snapshot.

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
10.200.0.1          - VPN Server (Host)
10.200.0.10-19      - Admins (reserved range)
10.200.0.20-29      - Instructors (reserved range)
10.200.0.100-109    - Red Team students (reserved range)
10.200.0.110-119    - Blue Team students (reserved range)
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
    
    # Cockpit - admins and instructors ONLY (effective for host service)
    iifname "wg0" ip saddr { 10.200.0.10-12 } tcp dport 9090 accept     # Cockpit - admins
    iifname "wg0" ip saddr { 10.200.0.20-21 } tcp dport 9090 accept     # Cockpit - instructors
    
    # Portainer nftables rules (INEFFECTIVE - see note below)
    iifname "wg0" ip saddr { 10.200.0.10-12 } tcp dport 9443 accept     # Portainer - admins
    iifname "wg0" ip saddr { 10.200.0.20-21 } tcp dport 9443 accept     # Portainer - instructors
    
    # Block Lab VM from VDS management services (defense in depth)
    iifname "virbr0" tcp dport { 22, 9090, 9443 } drop
    iifname "virbr0" accept              # Allow other Lab VM traffic
}
```

> ⚠️ **IMPORTANT - nftables vs Docker**: 
> - **Cockpit (9090)** runs directly on the host → nftables INPUT rules **are effective**
> - **Portainer (9443)** runs in Docker → nftables INPUT rules **are NOT effective** because Docker uses DNAT in PREROUTING before INPUT is evaluated. Portainer access is controlled via iptables DOCKER-USER chain (see below).
> - Students cannot access Cockpit (nftables) or Portainer (DOCKER-USER iptables)
> - Lab VM cannot reach VDS management ports
>
> ⚠️ **nftables + iptables coexistence**: Ubuntu 24.04 uses iptables-nft backend by default. Both firewall systems can run simultaneously, but care must be taken to avoid rule conflicts. In this setup, nftables handles host traffic and iptables handles Docker traffic only.

### Docker/Portainer Access Control (iptables DOCKER-USER)

Because Portainer runs in a Docker container, nftables INPUT rules alone cannot block access - Docker uses DNAT to forward traffic before the INPUT chain is evaluated. To block students from Portainer, we use the `DOCKER-USER` iptables chain:

```bash
# Allow admins and instructors (10.200.0.10-29)
sudo iptables -A DOCKER-USER -i wg0 -m iprange --src-range 10.200.0.10-10.200.0.29 -p tcp --dport 9443 -j ACCEPT

# Block all other VPN traffic to Portainer
sudo iptables -A DOCKER-USER -i wg0 -p tcp --dport 9443 -j DROP

# Allow all other traffic (required for Docker to function)
sudo iptables -A DOCKER-USER -j RETURN

# Save rules for persistence
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

**Result:**
| IP Range | Users | Portainer Access |
|----------|-------|------------------|
| 10.200.0.10-29 | Admins + Instructors | ✅ Allowed |
| 10.200.0.100+ | All students | ❌ Blocked |

> 💡 **Why 10.200.0.10-29?** The range is intentionally broader than currently assigned users (.10-.12 admins, .20-.21 instructors) to allow future growth without firewall changes. IPs .13-.19 and .22-.29 are reserved but not yet assigned. The iptables range approach is simpler than listing individual IPs and easier to maintain.
>
> 💡 New students added via `add-student.sh` get IPs in the 10.200.0.100+ range and are automatically blocked - no firewall changes needed.

### Host FORWARD Chain (Traffic Routing)

The VDS host routes traffic between VPN clients and the Lab VM. The FORWARD chain controls what traffic is allowed to pass through:

```nft
chain forward {
    policy drop;
    
    # Allow established/related (return traffic)
    ct state established,related accept
    
    # VPN ↔ Lab VM bidirectional
    ip saddr 10.200.0.0/24 ip daddr 192.168.122.0/24 accept  # VPN to Lab VM
    ip saddr 192.168.122.0/24 ip daddr 10.200.0.0/24 accept  # Lab VM to VPN
    
    # Lab VM to internet (controlled by lab.sh phases)
    iifname "virbr0" oifname != "wg0" accept                  # Lab VM outbound
    oifname "virbr0" iifname != "wg0" ct state established,related accept  # Return traffic
    
    # Everything else is logged and dropped
    log prefix "[nftables DROP FORWARD] " drop
}
```

**Allowed traffic flows:**
| Source | Destination | Allowed? |
|--------|-------------|----------|
| VPN clients | Lab VM | ✅ Yes |
| Lab VM | VPN clients | ✅ Yes |
| Lab VM | Internet | ✅ Yes (runtime control via lab.sh) |
| VPN client | VPN client | ❌ No (no inter-client routing) |
| Internet | Lab VM | ❌ No (except established) |

> 💡 **Security note**: VPN clients cannot directly communicate with each other through the VDS - only with the Lab VM network.

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
- Internet access is cut
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
> - Phase control runs on VDS, not on Lab VM
> - Student containers are NOT on services_net (L2 isolation) - prevents cross-team communication via shared network
> - Access to services is controlled via L3 iptables routing, allowing filtering even in prep mode

## Secrets Management

### Secrets NOT in Git

The following are excluded via `.gitignore`:
- `.env` files (database passwords, etc.)
- WireGuard private keys
- SSH private keys

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

Lab VM logs are stored locally. For this POC training environment, this is acceptable.

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

---
**Last Updated:** February 2026
