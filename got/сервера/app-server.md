# UNDE Infrastructure - Server Documentation

> **Last updated:** 2026-01-20  
> **Status:** App Server deployed, waiting for unde-api image

---

## Table of Contents
- [Infrastructure Overview](#infrastructure-overview)
- [Network Configuration](#network-configuration)
- [App Server Details](#app-server-details)
- [DB Server Details](#db-server-details)
- [Docker Services](#docker-services)
- [Credentials & Secrets](#credentials--secrets)
- [Deployment Commands](#deployment-commands)
- [Monitoring](#monitoring)

---

## Infrastructure Overview

```
                              Internet
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         Hetzner Cloud (Helsinki)                           │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   ┌────────────────────────┐  ┌────────────────────────┐  ┌─────────────┐  │
│   │      App Server        │  │     Push Server        │  │  DB Server  │  │
│   │  app-real.unde.life    │  │  push.unde.life        │  │db.unde.life │  │
│   │                        │  │                        │  │             │  │
│   │  Public: 46.62.233.30  │  │  Private: 10.1.0.4     │  │Private:     │  │
│   │  Private: 10.1.0.2     │  │                        │  │ 10.1.1.2    │  │
│   │                        │  │  Services:             │  │             │  │
│   │  Services:             │  │  - Redis Queue         │  │PostgreSQL 17│  │
│   │  - Nginx (80, 443)     │  │  - Celery Workers      │  │PgBouncer    │  │
│   │  - Redis Cache         │  │  - node_exporter       │  │ :6432       │  │
│   │  - Prometheus          │  │  - redis_exporter      │  │             │  │
│   │  - Grafana             │  │                        │  │Exporters:   │  │
│   │  - unde-api (pending)  │  │                        │  │ :9100,:9187 │  │
│   └───────────┬────────────┘  └───────────┬────────────┘  └──────┬──────┘  │
│               │                           │                      │         │
│               └───────────────┬───────────┴──────────────────────┘         │
│                               │                                            │
│                    10.1.0.0/16 (Private Network)                           │
│                               │                                            │
│               ┌───────────────▼───────────────┐                            │
│               │      Network Gateway          │                            │
│               │         10.1.0.1              │                            │
│               └───────────────┬───────────────┘                            │
│                               │                                            │
│               ┌───────────────▼───────────────┐                            │
│               │       GitLab Server           │                            │
│               │   gitlab-real.unde.life       │                            │
│               └───────────────────────────────┘                            │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Network Configuration

### App Server Network Interfaces

| Interface | IP Address | Netmask | Network | Purpose |
|-----------|------------|---------|---------|---------|
| **eth0** | 46.62.233.30 | /32 | Public | Internet access, SSH |
| **enp7s0** | 10.1.0.2 | /32 | Hetzner Private | DB, GitLab access |
| **docker0** | 172.17.0.1 | /16 | Docker default | Unused |
| **br-9a2f8e7699a2** | 172.18.0.1 | /16 | unde-network | Container network |
| **lo** | 127.0.0.1 | /8 | Loopback | Local services |

### IPv6
| Interface | Address |
|-----------|---------|
| eth0 | 2a01:4f9:c012:4d58::1/64 |

### Routing Table

```bash
# View routes
ip route show

# Current routes:
default via 172.31.1.1 dev eth0          # Internet gateway (Hetzner)
10.0.0.0/24 via 10.1.0.1 dev enp7s0      # GitLab network
10.1.0.0/16 via 10.1.0.1 dev enp7s0      # Private network (DB server)
172.17.0.0/16 dev docker0                 # Docker default bridge
172.18.0.0/16 dev br-9a2f8e7699a2        # unde-network bridge
```

### Key Routes Explained

| Destination | Gateway | Interface | Purpose |
|-------------|---------|-----------|---------|
| 0.0.0.0/0 (default) | 172.31.1.1 | eth0 | Internet traffic |
| 10.0.0.0/24 | 10.1.0.1 | enp7s0 | GitLab server (gitlab-real.unde.life) |
| 10.1.0.0/16 | 10.1.0.1 | enp7s0 | DB server (db.unde.life), Push server (push.unde.life) |

### DNS Configuration

```bash
# /etc/resolv.conf
nameserver 127.0.0.53    # systemd-resolved
options edns0 trust-ad
```

- **Local resolver:** systemd-resolved (127.0.0.53)
- **Upstream DNS:** Hetzner DNS servers

### Firewall Status

```bash
# UFW
ufw status
# Status: inactive

# iptables
iptables -L INPUT -n
# Chain INPUT (policy ACCEPT)
# No rules - firewall managed at Hetzner Cloud level
```

### Netplan Configuration

```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: "92:00:07:04:c3:ce"
      dhcp4: true
      set-name: "eth0"
      addresses:
        - "2a01:4f9:c012:4d58::1/64"
    enp7s0:
      dhcp4: true
      routes:
        - to: "10.0.0.0/24"
          via: "10.1.0.1"
```

### Listening Ports

| Port | Bind Address | Service | Access Level |
|------|--------------|---------|--------------|
| **22** | 0.0.0.0 | SSH | Public (key auth) |
| **80** | 0.0.0.0 | Nginx HTTP | Public → HTTPS redirect |
| **443** | 0.0.0.0 | Nginx HTTPS | Public |
| **3000** | 127.0.0.1, 10.1.0.2 | Grafana | Localhost + Internal |
| **8000** | 127.0.0.1 | unde-api (pending) | Localhost (via Nginx) |
| **8080** | 10.1.0.2 | Nginx stub_status | Internal only |
| **9090** | 127.0.0.1 | Prometheus | Localhost only |
| **9100** | 127.0.0.1 | Node Exporter | Localhost only |
| **9113** | 127.0.0.1 | Nginx Exporter | Localhost only |
| **9122** | 127.0.0.1 | Redis Exporter | Localhost only |

### Network Connectivity Matrix

| From | To | Port | Protocol | Status |
|------|-----|------|----------|--------|
| Internet | App:443 | HTTPS | TCP | ✅ Open |
| Internet | App:80 | HTTP | TCP | ✅ Open (redirect) |
| Internet | App:22 | SSH | TCP | ✅ Open |
| App | DB:6432 | PostgreSQL | TCP | ✅ Open |
| App | DB:9100 | node_exporter | TCP | ✅ Open |
| App | DB:9187 | postgres_exporter | TCP | ✅ Open |
| App | Push:9100 | node_exporter | TCP | ✅ Open |
| App | Push:9121 | redis_exporter | TCP | ✅ Open |
| App | GitLab:80 | HTTP | TCP | ✅ Open |
| Push | DB:6432 | PostgreSQL | TCP | ✅ Open |

### Docker Network (unde-network)

```bash
# Inspect network
docker network inspect unde-network

# Network details:
Name: unde-network
Driver: bridge
Subnet: 172.18.0.0/16
Gateway: 172.18.0.1
```

| Container | Service | Internal DNS |
|-----------|---------|--------------|
| unde-nginx | nginx | nginx |
| unde-redis-cache | redis-cache | redis-cache |
| unde-prometheus | prometheus | prometheus |
| unde-grafana | grafana | grafana |
| unde-api (pending) | unde-api | unde-api |

### /etc/hosts

```
127.0.0.1 localhost
127.0.1.1 App-Server
```

---

## App Server Details

| Parameter | Value |
|-----------|-------|
| **Hostname** | App-Server |
| **FQDN** | app-real.unde.life (public), app.unde.life (internal) |
| **Public IP** | 46.62.233.30 |
| **Private IP** | 10.1.0.2 |
| **OS** | Ubuntu 24.04.3 LTS |
| **Kernel** | Linux 6.8.0 |
| **CPU** | 8 vCPU (AMD EPYC) |
| **RAM** | 16 GB |
| **Storage** | 160 GB NVMe |
| **Provider** | Hetzner Cloud CX42 |
| **Location** | Helsinki, Finland |

### SSL Certificate
| Parameter | Value |
|-----------|-------|
| **Type** | Let's Encrypt |
| **Domain** | app-real.unde.life |
| **Expires** | 2026-04-20 |
| **Auto-renewal** | Daily at 3:00 (cron) |
| **Path** | /opt/unde/nginx/ssl/ |

---

## DB Server Details

| Parameter | Value |
|-----------|-------|
| **Hostname** | db01.unde.life |
| **FQDN** | db.unde.life |
| **Private IP** | 10.1.1.2 |
| **PgBouncer** | db.unde.life:6432 (10.1.1.2:6432) |
| **PostgreSQL** | 17 |
| **Database** | unde_main |
| **User** | undeuser |

### Exporters
| Exporter | Port | Metrics |
|----------|------|---------|
| node_exporter | 9100 | System metrics |
| postgres_exporter | 9187 | PostgreSQL metrics |

---

## Push Server Details

| Parameter | Value |
|-----------|-------|
| **FQDN** | push.unde.life |
| **Private IP** | 10.1.0.4 |
| **Purpose** | Celery workers, Redis Queue |

### Services
| Service | Port | Description |
|---------|------|-------------|
| Redis Queue | 6379 | Celery task queue (noeviction) |
| Celery Workers | - | Background task processing |

### Exporters
| Exporter | Port | Metrics |
|----------|------|---------|
| node_exporter | 9100 | System metrics |
| redis_exporter | 9121 | Redis queue metrics |

---

## fal.ai Servers

### Model Generator (10.1.0.5)

| Parameter | Value |
|-----------|-------|
| **Private IP** | 10.1.0.5 |
| **Purpose** | Batch AI model generation |
| **Queue** | generator_queue |
| **Workers** | 2 |
| **fal.ai API** | flux/dev |

### TryOn Service (10.1.0.6)

| Parameter | Value |
|-----------|-------|
| **Private IP** | 10.1.0.6 |
| **Purpose** | Real-time virtual try-on |
| **Queue** | tryon_queue |
| **Workers** | 4 |
| **fal.ai API** | flux-lora (primary), fashn (backup) |
| **Local Cache** | Redis for results caching |

### Communication

```
App Server (unde-api) → Redis (push.unde.life:6379) → Celery Workers
                              ↓
                    DB 4: Celery broker
                    DB 5: Result backend
```

### Prometheus Targets
| Job | Target | Status |
|-----|--------|--------|
| node-model-generator | 10.1.0.5:9100 | ✅ up |
| node-tryon-service | 10.1.0.6:9100 | ✅ up |

---

## Database Tables (fal.ai)

### model_library
Библиотека AI-моделей (аватаров) для virtual try-on.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| template_id | VARCHAR(100) | Unique template identifier |
| version | INTEGER | Template version |
| image_url | TEXT | Full-size image URL |
| thumbnail_url | TEXT | Preview image URL |
| gender | VARCHAR(20) | male/female/unisex |
| body_type | VARCHAR(20) | slim/regular/plus |
| pose | VARCHAR(50) | Pose description |
| style | VARCHAR(50) | Style category |
| metadata | JSONB | Additional data |
| created_at | TIMESTAMPTZ | Creation timestamp |

### tryon_requests
Лог запросов virtual try-on для аналитики.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | User reference |
| person_url_hash | VARCHAR(32) | MD5 hash of person URL |
| garment_url_hash | VARCHAR(32) | MD5 hash of garment URL |
| provider | VARCHAR(20) | flux/fashn/cache |
| cached | BOOLEAN | Whether result was cached |
| processing_time_ms | INTEGER | Processing duration |
| created_at | TIMESTAMPTZ | Request timestamp |

---

## Docker Services

### Running Services (7)

| Service | Container | Ports | Memory | Status |
|---------|-----------|-------|--------|--------|
| nginx | unde-nginx | 80, 443, 8080 (internal) | 256MB | ✅ |
| redis-cache | unde-redis-cache | 6379 (internal) | 1.25GB | ✅ |
| prometheus | unde-prometheus | 9090 (localhost) | 1GB | ✅ |
| grafana | unde-grafana | 3000 (localhost+internal) | 512MB | ✅ |
| node-exporter | unde-node-exporter | 9100 (localhost) | 128MB | ✅ |
| redis-exporter-cache | unde-redis-exporter-cache | 9122 (localhost) | 64MB | ✅ |
| nginx-exporter | unde-nginx-exporter | 9113 (localhost) | 64MB | ✅ |

### Pending Services (1)

| Service | Container | Ports | Memory | Status |
|---------|-----------|-------|--------|--------|
| unde-api | unde-api | 8000 (localhost) | 2GB | ⏳ Waiting for image |

---

## Credentials & Secrets

### .env location
```
/opt/unde/.env
```

### Variables
```bash
# Redis
REDIS_CACHE_PASSWORD=K3zN#bk$iG0ZqKX

# Grafana
GF_SECURITY_ADMIN_PASSWORD=#m2bO6l0WSC7r4t

# Database
DATABASE_URL=postgresql://undeuser:X37nLbzPI2jeL@10.1.1.2:6432/unde_main?prepared_statement_cache_size=0

# Redis URL
REDIS_CACHE_URL=redis://:K3zN#bk$$iG0ZqKX@redis-cache:6379/0

# API
APP_ENV=production
LOG_LEVEL=info

# External APIs (TODO)
INTELISTYLE_API_KEY=
STT_API_KEY=
TTS_API_KEY=
NAVIGATION_API_URL=
```

---

## Deployment Commands

```bash
# Start services
cd /opt/unde
docker compose up -d

# Start with API
docker compose --profile api up -d

# Status
docker compose ps

# Logs
docker compose logs -f <service>

# Health check
./scripts/health-check.sh

# Network debug
docker network inspect unde-network
ss -tlnp
ip route show
```

---

## Monitoring

### Prometheus Targets

| Job | Target | Server | Status |
|-----|--------|--------|--------|
| prometheus | localhost:9090 | App | ✅ up |
| node-app | node-exporter:9100 | App | ✅ up |
| node-db | db.unde.life:9100 | DB | ✅ up |
| node-push | push.unde.life:9100 | Push | ✅ up |
| node-model-generator | 10.1.0.5:9100 | fal.ai | ✅ up |
| node-tryon-service | 10.1.0.6:9100 | fal.ai | ✅ up |
| postgresql | db.unde.life:9187 | DB | ✅ up |
| redis-cache | redis-exporter-cache:9121 | App | ✅ up |
| redis-push-queue | push.unde.life:9121 | Push | ✅ up |
| nginx | nginx-exporter:9113 | App | ✅ up |
| unde-api | unde-api:8000 | App | ✅ up |

### URLs

| Service | URL |
|---------|-----|
| Main | https://app-real.unde.life/ |
| Health | https://app-real.unde.life/health |
| Health (fal.ai) | https://app-real.unde.life/health/fal |
| API | https://app-real.unde.life/api/ |
| API Docs | https://app-real.unde.life/api/docs |
| TryOn (sync) | POST https://app-real.unde.life/api/v1/tryon/sync |
| TryOn (async) | POST https://app-real.unde.life/api/v1/tryon/async |
| TryOn (status) | GET https://app-real.unde.life/api/v1/tryon/status/{task_id} |
| Grafana | https://app-real.unde.life/grafana/ |
| Grafana (internal) | http://10.1.0.2:3000/ |

---

## Quick Network Commands

```bash
# Check connectivity to DB
ping -c 3 db.unde.life  # 10.1.1.2

# Check PgBouncer
nc -zv db.unde.life 6432

# Check GitLab
curl -s http://gitlab-real.unde.life/

# Check routes
ip route show

# Check listening ports
ss -tlnp

# Check Docker networks
docker network ls
docker network inspect unde-network

# DNS lookup
dig app-real.unde.life
```

---

*Document generated: 2026-01-20*  
*Repository: http://gitlab-real.unde.life/unde/unde-app*
