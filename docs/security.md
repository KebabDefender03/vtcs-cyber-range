# VTCS Cyber Range - Security Documentation

## Security Model Overview

The VTCS Cyber Range implements a defense-in-depth security model with multiple layers of protection to ensure that lab activities remain contained and do not impact external systems.

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
| SSH (Lab VM) | TCP/22 | VPN only | Per-user SSH keys + ForceCommand |

### User Roles

| Role | Access Level | Capabilities |
|------|--------------|--------------|
| Admin | Full | Host SSH, Cockpit, Lab VM, all containers |
| Instructor | Lab VM | Lab management, workspace monitoring |
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

```nft
# Default policies
chain input { policy drop; }
chain forward { policy drop; }
chain output { policy accept; }

# Allowed inbound (from internet)
- UDP 51820 (WireGuard) from any
- ICMP from any

# Allowed inbound (from VPN 10.200.0.0/24)
- TCP 22 (SSH)
- TCP 9090 (Cockpit)

# Allowed inbound (from Lab VM 192.168.122.0/24)
- All (trusted internal)

# Forwarding
- VPN ↔ Lab VM network (192.168.122.0/24)
- Lab VM NAT for controlled egress
```

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
- No routing between blue_net and red_net
- services_net is shared for controlled target access

## Egress Control

### Default: No Internet Access

By default, workspace containers have no route to the internet:
- Docker networks are internal bridges
- No NAT masquerading for container traffic to internet
- Prevents data exfiltration and C2 communication

### Controlled Egress (If Required)

If scenarios require internet access (e.g., downloading tools):

**Option 1: Pre-built Images**
- Include all necessary tools in container images
- No runtime internet access needed

**Option 2: Proxy with Allowlist**
```yaml
# Add to docker-compose.yml
proxy:
  image: squid
  networks:
    - services_net
  environment:
    - ALLOWED_DOMAINS=github.com,*.githubusercontent.com
```

**Option 3: Time-limited Access**
```bash
# Temporarily enable egress
iptables -t nat -A POSTROUTING -s 172.20.0.0/16 -j MASQUERADE

# Disable after updates
iptables -t nat -D POSTROUTING -s 172.20.0.0/16 -j MASQUERADE
```

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

**Simple approach**: Use Cockpit's built-in monitoring instead of separate tools.

**Why Cockpit instead of Grafana/Prometheus?**
- No additional services to secure/patch
- No privileged containers needed
- Already VPN-only by design
- VM console access included
- Sufficient for training environment

**Cockpit provides:**
- CPU, memory, disk, network metrics
- VM management and console
- Service status monitoring
- Log viewing (journalctl)

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
- Consider centralized logging for production use

## Incident Response

### Suspected Compromise

1. **Isolate**: Disconnect VDS from internet (Contabo console)
2. **Preserve**: Snapshot VMs before investigation
3. **Investigate**: Review logs for indicators
4. **Recover**: Restore from known-good snapshot
5. **Report**: Document incident for learning

### Emergency Reset

```bash
# Full environment reset (destroys all data)
cd /opt/cyberlab
./scripts/lab.sh reset

# Or nuclear option - restore Lab VM snapshot
virsh snapshot-revert labvm clean-baseline
```

## Security Hardening Checklist

### Host Hardening
- [x] Disable root SSH login (after admin user created)
- [x] SSH key-only authentication
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
