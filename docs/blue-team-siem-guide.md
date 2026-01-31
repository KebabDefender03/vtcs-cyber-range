# Blue Team SIEM Deployment Guide

## Overview

During the **Preparation Phase**, the Blue Team can deploy their own SIEM (Security Information and Event Management) tool to monitor the lab environment. This is a realistic exercise - real blue teams manage their own security tools.

## Why Bring Your Own SIEM?

- **Educational**: Students learn SIEM deployment and configuration
- **Realistic**: Real blue teams don't have pre-built monitoring
- **Flexible**: Choose tools that fit your team's expertise
- **Scalable**: Each lab group has independent monitoring

## Available Data Sources

Once deployed, your SIEM can collect logs from:

| Source | Method | Data | Access |
|--------|--------|------|--------|
| **Network Traffic** | tcpdump from blue container | TCP/UDP packets, HTTP requests | From your blue container |
| **Workstation Activity** | Network capture (automatic) | HTTP requests to webapp, DB queries | Visible in network traffic |
| **Application Logs** | SSH to workstation | DVWA logs, system events | Via SSH to workstation (if enabled) |
| **System Events** | Log files on workstation | Auth logs, service logs | Via SSH to workstation (if enabled) |

**Note**: You cannot access other containers' internals or view their logs. You can only:
- Capture network traffic from your blue container
- SSH into workstation container (if instructor enables it)
- Analyze traffic patterns and timing

## Option 1: Grafana + Loki (Recommended for Beginners)

**Lightweight, fast to deploy, perfect for learning**

```bash
# During Preparation Phase, in blue1 container:
cd /tmp

# Create docker-compose for SIEM
cat > siem-compose.yml <<EOF
version: '3.8'
services:
  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - ./loki-config.yml:/etc/loki/local-config.yml
    command: -config.file=/etc/loki/local-config.yml
    networks:
      - siem

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=BlueTeam2024
    networks:
      - siem

networks:
  siem:
EOF

# Start SIEM stack
docker compose -f siem-compose.yml up -d
```

**Access**: http://workstation:3000 (from your container)
**Default credentials**: admin / BlueTeam2024

---

## Option 2: ELK Stack (Elasticsearch + Logstash + Kibana)

**More powerful, better for larger deployments**

```bash
# Deploy ELK in blue team network
docker run -d \
  --name elasticsearch \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  --network services_net \
  docker.elastic.co/elasticsearch/elasticsearch:8.0.0

docker run -d \
  --name kibana \
  -p 5601:5601 \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  --network services_net \
  docker.elastic.co/kibana/kibana:8.0.0
```

**Access**: http://workstation:5601
**Features**: Index patterns, visualizations, dashboards

---

## Option 3: Wazuh (Full-Featured SIEM)

**Enterprise-grade, includes threat detection**

```bash
# Deploy Wazuh manager
docker run -d \
  --name wazuh \
  -p 1514:1514 \
  -p 1515:1515 \
  -p 514:514/udp \
  -p 55000:55000 \
  --network services_net \
  wazuh/wazuh:4.7.0
```

**Access**: https://workstation:55000
**Default**: wazuh / wazuh

---

## Collecting Evidence for Analysis

### Network Traffic (Primary Method)

```bash
# From your blue container:
tcpdump -i eth0 -w /tmp/capture.pcap 'host webapp'
# Download and analyze in Wireshark
```

This captures:
- All HTTP requests to webapp (visible in workstation activity)
- Database traffic (if visible on network)
- Login attempts
- Attack payloads

### Workstation Activity (Automatic)

The workstation container generates realistic traffic automatically:
- HTTP requests to webapp every 10-30 seconds
- Mix of normal browsing, logins, file operations
- Visible in your network captures
- Can be analyzed for baseline vs. attack patterns

### Application Logs (If SSH Access Available)

```bash
# Only if instructor enables SSH to workstation:
ssh root@workstation
tail -f /var/log/apache2/access.log
# Or check DVWA logs
```

### From DVWA / Webapp Container

```bash
# Network-based analysis only
# Monitor HTTP responses from webapp
# Analyze payload reflections in responses
```

---

## Example: Detect Red Team Attack

**Scenario**: Red team launches SQL injection attack against DVWA

**What your SIEM will show:**

1. **Alert in DVWA logs**:
   ```
   WARNING: SQL Injection attempt detected
   User-Agent: sqlmap/1.4.9.12
   SQL: SELECT * FROM users WHERE id='1' UNION SELECT...
   ```

2. **Network traffic spike**:
   ```
   192.168.122.2 (red1) → 172.20.3.10:80 (webapp)
   Requests/minute: 150+ (vs normal 5)
   ```

3. **Database log anomaly**:
   ```
   Unique SQL queries per minute: 50+ (vs normal 2)
   Failed queries: 20+
   ```

4. **Grafana visualization**:
   - Graph showing request rate spike
   - Top source IPs
   - Top User-Agents
   - Failed login attempts

---

## Blue Team Workflow

### Preparation Phase (First 30 minutes)

1. ✅ Deploy SIEM of choice
2. ✅ Connect to log sources (docker, network)
3. ✅ Create detection rules for common attacks
4. ✅ Set up dashboards for monitoring
5. ✅ Test connectivity to webapp / database

**Example rule**: Alert if HTTP 500 errors spike

### Combat Phase

1. 🔴 Monitor incoming attacks
2. 🔴 Correlate alerts across log sources
3. 🔴 Document attack techniques
4. 🔴 Respond to incidents
5. 🔴 Defend against threats

---

## Security Note: Blue Team SIEM Access

Your SIEM runs **inside** the lab network, so:

- ✅ Accessible from your blue containers
- ✅ Can see all workstation traffic
- ✅ Can monitor service logs
- ❌ NOT accessible from outside (VPN isolation)
- ❌ NOT accessible to red team (network segmentation)

If red team compromises a container on `services_net`, they could potentially access logs. Your SIEM should implement access controls.

---

## Pre-Built SIEM Templates

Download from `/opt/cyberlab/siem-templates/`:

- `loki-grafana-compose.yml` - Quick start Loki+Grafana
- `elk-compose.yml` - ELK stack
- `wazuh-compose.yml` - Wazuh manager
- `tcpdump-capture.sh` - Network traffic capture script

---

## Questions / Support

- Ask your instructor for SIEM recommendations
- Check lab documentation for network layout
- Coordinate with teammates on monitoring strategy

**Good luck defending the lab! 🛡️**
