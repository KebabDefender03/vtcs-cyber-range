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

3. **Start Lab Environment** (on Lab VM)
   ```bash
   cd /opt/cyberlab
   ./scripts/lab.sh start
   ```

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
│       ├── docker-compose.yml
│       ├── .env.example
│       ├── images/           # Container Dockerfiles
│       └── init-db/          # Database initialization
├── scripts/
│   └── lab.sh                # Lab management CLI
├── docs/
│   ├── architecture.md       # System architecture
│   ├── security.md           # Security controls
│   └── runbook.md            # Step-by-step deployment
├── Makefile                  # Convenience targets
└── README.md
```

## Lab Management

```bash
# Start the lab
./scripts/lab.sh start

# Check status
./scripts/lab.sh status

# View logs
./scripts/lab.sh logs -c webapp -f

# Open shell in workspace
./scripts/lab.sh shell -c red1

# Reset to clean state
./scripts/lab.sh reset

# Show SSH connection info
./scripts/lab.sh ssh-info
```

## Security Features

- **VPN-only access**: No services exposed to internet except WireGuard
- **Network segmentation**: Red/Blue teams fully isolated, shared target zone only
- **Per-user SSH keys**: Each user has unique keypair with ForceCommand
- **Egress control**: Containers have no internet access by default
- **Resource limits**: CPU/memory limits prevent resource exhaustion
- **Firewall layers**: Host nftables + Lab VM nftables + Docker networks
- **Logging**: VPN, SSH, container lifecycle events logged

See [docs/security.md](docs/security.md) for complete security documentation.

## Authentication

Access is via SSH keys and/or passwords (admins only):

| Role | Access | Auth Method |
|------|--------|-------------|
| Admin | VDS host + Lab VM (full shell) | SSH key OR password |
| Instructor | Lab VM (shell + docker) | SSH key |
| Student | Lab VM → auto-exec into container | SSH key |

See [MASTER-DOCUMENTATION.md](MASTER-DOCUMENTATION.md) for key distribution.

## Recovery Options

1. **Container restart**: `docker restart <container>`
2. **Full lab reset**: `./scripts/lab.sh reset`
3. **VM snapshot restore**: `virsh snapshot-revert labvm clean-baseline`

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Security Controls](docs/security.md)
- [Deployment Runbook](docs/runbook.md)

## License

Educational use only. Not for production deployment.

## Contributors

VTCS Cybersecurity Course - Project 2
