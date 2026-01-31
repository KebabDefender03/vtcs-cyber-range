# VTCS Cyber Range POC

A containerized red/blue team training environment for cybersecurity education.

## Overview

This project provides an isolated, reproducible lab environment for security training exercises. It runs on a Contabo VDS and provides:

- **6 Student Workspaces**: 3 Red team + 3 Blue team containers
- **Target Services**: Vulnerable web application + database
- **VPN-only Access**: WireGuard as the sole entry point
- **Segmented Networks**: Isolated team networks with shared target zone
- **Easy Reset**: Docker-based recovery + VM snapshots

## Architecture

```
Internet → WireGuard VPN → VDS Host → KVM Lab VM → Docker Containers
                                                    ├── Blue Team (×3)
                                                    ├── Red Team (×3)
                                                    └── Services (Web, DB)
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture.

## Quick Start

### Prerequisites

- Contabo VDS (3 cores, 24GB RAM, Ubuntu 24.04)
- WireGuard client on your machine

### Deployment

1. **Clone this repo**
   ```bash
   git clone <repo-url>
   cd VDS
   ```

2. **Deploy to VDS** (see [docs/runbook.md](docs/runbook.md) for details)
   ```bash
   # Upload scripts
   scp -r infra/host root@<VDS-IP>:/root/cyberlab-setup/
   
   # SSH and run setup
   ssh root@<VDS-IP>
   cd /root/cyberlab-setup/host
   chmod +x *.sh
   ./01-initial-setup.sh
   ./02-wireguard-setup.sh
   # ... continue with runbook
   ```

3. **Start Lab Environment** (via Portainer)
   - Access Portainer: https://10.200.0.1:9443
   - Deploy the "vtcs" stack from GitHub repository
   - Stack is deployed directly from `scenarios/base/docker-compose.yml`

## Repository Structure

```
VDS/
├── infra/
│   ├── host/                 # VDS host setup scripts
│   │   ├── 01-initial-setup.sh
│   │   ├── 02-wireguard-setup.sh
│   │   ├── 03-firewall-setup.sh
│   │   ├── 04-cockpit-hardening.sh
│   │   └── 05-create-labvm.sh
│   └── labvm/                # Lab VM bootstrap
│       └── 01-labvm-bootstrap.sh
├── scenarios/
│   └── base/                 # Default lab scenario
│       └── docker-compose.yml  # Deployed via Portainer from GitHub
├── scripts/
│   └── lab.sh                # Phase control CLI (runs on VDS)
├── docs/
│   ├── architecture.md       # System architecture
│   ├── security.md           # Security controls
│   └── runbook.md            # Step-by-step deployment
├── Makefile                  # Convenience targets
└── README.md
```

> **Note**: Docker Compose is deployed via Portainer from this GitHub repo, not stored locally on Lab VM.

## Lab Management

### Container Management (via Portainer)

Container start/stop/logs/restart is done via Portainer: https://10.200.0.1:9443

### Workstation Activity Simulation

The `workstation` container automatically generates realistic traffic patterns:
- **Every 10-30 seconds**: One random activity from the following:
  - HTTP GET requests to `http://webapp/` and `/index.php`
  - Login attempts to `/login.php` with dummy credentials
  - Access to vulnerable pages (`/vulnerabilities/sqli/`, `/vulnerabilities/xss_r/`)
  - Database queries (`SELECT` from users table)
  - Admin panel access (`/admin.php`)
  - File operations (create/delete temp files)
  - Network connectivity checks (ping to webapp/database)

**Blue team visibility**: Network traffic capture via tcpdump from your blue container shows all HTTP requests, response codes, and timing patterns. This allows analysis of:
- Request frequency and types
- Response times
- Error patterns
- Attack detection (spike in requests, 403/500 errors)

### Phase Control (via lab.sh)

Phase control runs on VDS Host (as admin or instructor):

```bash
# Preparation phase: Internet ON, cross-team attacks OFF
sudo /opt/cyberlab/scripts/lab.sh prep

# Combat phase: Internet OFF, cross-team attacks ON  
sudo /opt/cyberlab/scripts/lab.sh combat

# Check current phase
sudo /opt/cyberlab/scripts/lab.sh phase
```

| Phase | Internet | Red ↔ Blue | Duration |
|-------|----------|------------|----------|
| **Preparation** | ✅ ON | ❌ OFF | First ~30 min |
| **Combat** | ❌ OFF | ✅ ON | Rest of session |

## Security Features

- **VPN-only access**: No services exposed to internet except WireGuard
- **Phase-based control**: Internet and cross-team access controlled per phase
- **VDS-based control**: All control scripts run on VDS (Lab VM is expendable)
- **Per-user SSH keys**: Each user has unique keypair with ForceCommand
- **Egress control**: Containers have no internet access by default
- **Resource limits**: CPU/memory limits prevent resource exhaustion
- **Firewall layers**: Host nftables + iptables + Lab VM firewall + Docker networks
- **Logging**: VPN, SSH, container lifecycle events logged
- **GUI Management**: Portainer (containers) + Cockpit (VM/snapshots) via VPN only

See [docs/security.md](docs/security.md) for complete security documentation.

## Authentication

Access is via SSH keys (password auth is disabled for admins):

| Role | Access | Auth Method |
|------|--------|-------------|
| Admin | VDS host + Lab VM (full shell) | SSH key only |
| Instructor | VDS host (lab.sh only) + Portainer + Cockpit | Password |
| Student | VDS host → ForceCommand → container | SSH key only |

> 💡 **Admins**: Use `ssh labvm` from VDS to connect to Lab VM (SSH config auto-selects key).
> 💡 **Instructors**: Use Portainer (https://10.200.0.1:9443) for container management.

See [MASTER-DOCUMENTATION.md](MASTER-DOCUMENTATION.md) for full access matrix.

## Recovery Options

1. **Container restart**: Via Portainer (https://10.200.0.1:9443)
2. **Full lab reset**: Restore snapshot via Cockpit or `virsh snapshot-revert labvm clean-baseline`

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Security Controls](docs/security.md)
- [Deployment Runbook](docs/runbook.md)

## License

Educational use only. Not for production deployment.

## Contributors

VTCS Cybersecurity Course - Project 2
