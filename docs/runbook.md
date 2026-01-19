# VTCS Cyber Range - Deployment Runbook

## Prerequisites

- Contabo VDS with:
  - 3+ CPU cores
  - 24 GB RAM
  - Ubuntu 24.04 LTS installed
  - Root SSH access
- Local machine with:
  - SSH client
  - WireGuard client
  - Git (for cloning this repo)

## Phase 1: Host Setup

### Step 1.1: Connect to VDS

```bash
# From your local machine
ssh root@<VDS_IP>
```

### Step 1.2: Upload Setup Scripts

```bash
# From your local machine (in repo directory)
scp -r infra/host root@<VDS_IP>:/root/cyberlab-setup/
```

### Step 1.3: Run Initial Setup

```bash
# On the VDS
cd /root/cyberlab-setup/host
chmod +x *.sh

# Run initial setup (updates, packages, fail2ban)
./01-initial-setup.sh
```

**Expected output**: System updates, package installation, fail2ban configured.

### Step 1.4: Configure WireGuard VPN

```bash
# Still on VDS
./02-wireguard-setup.sh
```

**Expected output**: WireGuard server configured, keys generated.

### Step 1.5: Create Admin VPN Client

```bash
# Create your admin VPN config
/etc/wireguard/add-vpn-client.sh admin 10
```

**Expected output**: Client config at `/etc/wireguard/clients/admin/admin.conf`

### Step 1.6: Download and Install VPN Config

```bash
# From your local machine
scp root@<VDS_IP>:/etc/wireguard/clients/admin/admin.conf ~/admin.conf

# Import into WireGuard client (varies by OS)
# Windows: Import tunnel in WireGuard app
# Linux: sudo cp admin.conf /etc/wireguard/ && sudo wg-quick up admin
# macOS: Import in WireGuard app
```

### Step 1.7: Test VPN Connection

```bash
# Activate VPN tunnel, then:
ping 10.200.0.1  # Should respond

# Test SSH via VPN
ssh root@10.200.0.1  # Should connect
```

### Step 1.8: Apply Firewall Rules

⚠️ **WARNING**: Only run this AFTER confirming VPN works!

```bash
# On VDS (via VPN SSH)
cd /root/cyberlab-setup/host
./03-firewall-setup.sh
```

**Expected output**: nftables rules applied, VPN-only access enforced.

### Step 1.9: Verify Lockdown

```bash
# From local machine (VPN disconnected)
ssh root@<VDS_PUBLIC_IP>  # Should timeout/fail

# With VPN connected
ssh root@10.200.0.1  # Should work
```

### Step 1.10: Configure Cockpit

```bash
# On VDS (via VPN)
./04-cockpit-hardening.sh
```

**Expected output**: Cockpit hardened, labadmin user created.

**Test**: Access https://10.200.0.1:9090 via browser (with VPN active)

---

## Phase 2: Lab VM Creation

### Step 2.1: Create Lab VM

```bash
# On VDS
./05-create-labvm.sh
```

**Expected output**: VM created, Ubuntu installer started.

### Step 2.2: Complete Ubuntu Installation

Access VM console via Cockpit (https://10.200.0.1:9090):
1. Navigate to "Virtual Machines" → "labvm"
2. Click "Console" tab
3. Complete Ubuntu Server installation:
   - Hostname: `labvm`
   - Username: `labadmin`
   - Password: (your choice)
   - Install OpenSSH Server: Yes
   - No additional snaps needed

### Step 2.3: Get Lab VM IP

After installation completes:

```bash
# On VDS
virsh domifaddr labvm
# Note the IP (likely 192.168.122.x)
```

### Step 2.4: Bootstrap Lab VM

```bash
# From VDS
scp /root/cyberlab-setup/infra/labvm/01-labvm-bootstrap.sh labadmin@192.168.122.X:~/

# SSH to Lab VM and run bootstrap
ssh labadmin@192.168.122.X
sudo bash ~/01-labvm-bootstrap.sh
```

**Expected output**: Docker installed, firewall configured, directory structure created.

---

## Phase 3: Deploy Lab Scenarios

### Step 3.1: Upload Scenario Files

```bash
# From your local machine (in repo directory)
# First, copy to VDS
scp -r scenarios scripts Makefile root@10.200.0.1:/tmp/cyberlab/

# Then from VDS to Lab VM
ssh root@10.200.0.1
scp -r /tmp/cyberlab/* labadmin@192.168.122.X:/opt/cyberlab/
```

### Step 3.2: Start Lab Environment

```bash
# On Lab VM
cd /opt/cyberlab
chmod +x scripts/*.sh

# Build and start
./scripts/lab.sh build
./scripts/lab.sh start
```

**Expected output**: All containers started.

### Step 3.3: Verify Lab Status

```bash
./scripts/lab.sh status
```

**Expected output**:
```
=== Container Status ===
NAME       STATUS         PORTS
blue1      Up             22/tcp
blue2      Up             22/tcp
blue3      Up             22/tcp
red1       Up             22/tcp
red2       Up             22/tcp
red3       Up             22/tcp
webapp     Up             127.0.0.1:8080->80/tcp
database   Up             3306/tcp
```

### Step 3.4: Get Workspace Connection Info

```bash
./scripts/lab.sh ssh-info
```

---

## Phase 4: Create Student VPN Clients

### Step 4.1: Create VPN Configs for All Users

```bash
# On VDS
cd /etc/wireguard

# Admins (VPN IPs: 10.200.0.10-12)
./add-vpn-client.sh admin 10
./add-vpn-client.sh admin2 11
./add-vpn-client.sh admin3 12

# Instructors (VPN IPs: 10.200.0.20-21)
./add-vpn-client.sh instructor1 20
./add-vpn-client.sh instructor2 21

# Red team (VPN IPs: 10.200.0.100-102)
./add-vpn-client.sh red1 100
./add-vpn-client.sh red2 101
./add-vpn-client.sh red3 102

# Blue team (VPN IPs: 10.200.0.110-112)
./add-vpn-client.sh blue1 110
./add-vpn-client.sh blue2 111
./add-vpn-client.sh blue3 112
```

### Step 4.2: Distribute Configs Securely

```bash
# Collect all configs
cd /etc/wireguard/clients
tar czf /tmp/student-vpn-configs.tar.gz */

# Download to your machine (then distribute via secure channel)
scp root@10.200.0.1:/tmp/student-vpn-configs.tar.gz ./
```

⚠️ Distribute configs via secure channel (not email/chat).

---

## Phase 5: Create Snapshots

### Step 5.1: Clean State Snapshot

```bash
# On VDS, ensure lab is in clean state
ssh labadmin@192.168.122.X "cd /opt/cyberlab && ./scripts/lab.sh reset"

# Wait for reset to complete, then create snapshot
virsh snapshot-create-as labvm clean-baseline "Clean lab baseline"
```

### Step 5.2: List Snapshots

```bash
virsh snapshot-list labvm
```

---

## Common Operations

### Start Lab Session

```bash
# On Lab VM
cd /opt/cyberlab
./scripts/lab.sh start
```

### End Lab Session

```bash
./scripts/lab.sh stop
```

### Reset Between Sessions

```bash
./scripts/lab.sh reset
```

### Full Reset (Snapshot Restore)

```bash
# On VDS
virsh snapshot-revert labvm clean-baseline
virsh start labvm
```

### View Logs

```bash
# All containers
./scripts/lab.sh logs

# Specific container
./scripts/lab.sh logs -c webapp -f
```

### Shell into Container

```bash
./scripts/lab.sh shell -c red1
```

---

## Troubleshooting

### VPN Not Connecting

1. Check WireGuard is running: `systemctl status wg-quick@wg0`
2. Check firewall allows UDP 51820: `nft list ruleset | grep 51820`
3. Check peer config matches: `wg show`

### Can't SSH After Firewall Setup

1. Connect via Contabo web console
2. Check nftables: `nft list ruleset`
3. Temporarily allow SSH: `nft add rule inet filter input tcp dport 22 accept`

### Containers Not Starting

1. Check Docker: `systemctl status docker`
2. Check compose: `docker compose logs`
3. Check resources: `free -h`, `df -h`

### Lab VM Network Issues

1. Check libvirt network: `virsh net-list`
2. Check virbr0: `ip addr show virbr0`
3. Restart network: `virsh net-destroy default && virsh net-start default`

---

## Appendix: Quick Reference

### IP Addresses

| Component | IP Address |
|-----------|------------|
| VDS Public | 62.171.146.215 |
| VDS VPN | 10.200.0.1 |
| Lab VM | 192.168.122.10 |
| blue_net | 172.20.1.0/24 |
| red_net | 172.20.2.0/24 |
| services_net | 172.20.3.0/24 |
| Admin VPN IPs | 10.200.0.10-12 |
| Instructor VPN IPs | 10.200.0.20-21 |
| Red Team VPN IPs | 10.200.0.100-102 |
| Blue Team VPN IPs | 10.200.0.110-112 |

### Default Credentials

| System | Username | Authentication |
|--------|----------|----------------|
| VDS | admin1/2/3 | SSH key (host_adminX.key) |
| VDS | root | SSH key (admin1 key authorized) + Contabo VNC password |
| Lab VM | labadmin1/2/3 | `ssh labvm` from VDS (auto-uses key) |
| Lab VM | instructor1/2 | SSH key (labvm_instructorX.key) |
| Lab VM | red1/2/3, blue1/2/3 | SSH key + ForceCommand |
| WebApp DB | labuser | labpass123 |

### Important Files

| File | Location | Purpose |
|------|----------|---------|
| WireGuard config | `/etc/wireguard/wg0.conf` | VPN server |
| Firewall rules | `/etc/nftables.conf` | Host firewall |
| Docker compose | `/opt/cyberlab/scenarios/base/docker-compose.yml` | Lab definition |
| Lab script | `/opt/cyberlab/scripts/lab.sh` | Management CLI |
