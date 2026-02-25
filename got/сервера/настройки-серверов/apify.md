# Apify Server — Full Description

## Hardware

| Parameter       | Value                                    |
|-----------------|------------------------------------------|
| CPU             | Intel Xeon (Skylake, IBRS), 2 vCPU       |
| RAM             | 3.7 GB (no swap)                         |
| Disk            | 38.1 GB SSD (`/dev/sda1`, 37.9 GB usable) |
| Public IP       | 89.167.110.186                           |
| Private IP      | 10.1.0.9 (internal network)              |

## OS

| Parameter       | Value                          |
|-----------------|--------------------------------|
| OS              | Ubuntu 24.04.3 LTS (Noble)     |
| Kernel          | 6.8.0-90-generic               |
| Hostname        | `apify`                        |
| Timezone        | UTC                            |

## Installed Software

| Component        | Version    | How installed              | Status   |
|------------------|------------|----------------------------|----------|
| Docker Engine    | 29.2.1     | Official Docker repo (apt) | active   |
| Docker Compose   | v5.0.2     | Docker plugin              | active   |
| node_exporter    | 1.8.2      | GitHub binary + systemd    | active   |
| Python           | 3.12.3     | System (Ubuntu)            | —        |
| Git              | 2.43.0     | System (Ubuntu)            | —        |
| psql client      | (system)   | apt                        | —        |
| redis-cli        | (system)   | apt                        | —        |

## Listening Ports

| Port  | Service          | Bind address |
|-------|------------------|--------------|
| 22    | sshd             | 0.0.0.0      |
| 9100  | node_exporter    | 0.0.0.0      |

Docker containers do not expose ports — they connect outbound to Redis and PostgreSQL.

## Docker Containers

| Container         | Image                  | Size   | Role                          | Status |
|-------------------|------------------------|--------|-------------------------------|--------|
| apify-collector   | 1-apify-collector      | 238 MB | Celery worker (concurrency=2) | Up     |
| apify-beat        | 1-celery-beat          | 238 MB | Celery beat scheduler         | Up     |

### Container Config
- **Restart policy**: `unless-stopped`
- **Memory limit**: 2 GB (apify-collector)
- **Env file**: `.env` (not in git)
- **Base image**: `python:3.12-slim`

## Application Architecture

```
                    ┌────────────────┐
                    │  Celery Beat   │  (apify-beat container)
                    │  crontab       │
                    └───────┬────────┘
                            │ enqueue task
                            ▼
┌──────────┐     ┌────────────────────┐     ┌──────────────┐
│  Redis   │◄────│  Celery Worker     │────►│  Apify Cloud │
│ 10.1.0.4 │     │ (apify-collector)  │     │  (API call)  │
│ :6379/7  │     └────────┬───────────┘     └──────────────┘
└──────────┘              │ upsert results
                          ▼
                ┌──────────────────┐
                │  PostgreSQL      │
                │  10.1.0.8:6432   │
                │  (PgBouncer)     │
                │  DB: unde_staging│
                └──────────────────┘
```

## Schedule

| Brand  | Apify Task ID       | Day    | Time (UTC) | Status     |
|--------|---------------------|--------|------------|------------|
| Zara   | z1psVOTyIKFdU5N9n   | Sunday | 02:00      | Active     |
| Bershka | —                  | Sunday | 03:00      | Not created |
| Pull&Bear | —               | Sunday | 04:00      | Not created |
| Stradivarius | —            | Sunday | 05:00      | Not created |
| Massimo Dutti | —           | Sunday | 06:00      | Not created |
| Oysho  | —                   | Sunday | 07:00      | Not created |

## External Dependencies

| Service     | Host          | Port  | Via         | Auth                  |
|-------------|---------------|-------|-------------|-----------------------|
| PostgreSQL  | 10.1.0.8      | 6432  | PgBouncer   | user=apify, password  |
| PostgreSQL  | 10.1.0.8      | 5432  | Direct      | (same)                |
| Redis       | 10.1.0.4      | 6379  | Direct      | password, DB=7        |
| Apify Cloud | api.apify.com | 443   | HTTPS       | API token             |
| GitLab      | gitlab-real.unde.life | 80 | HTTP     | PAT (credential helper) |

## Database Tables Used

### `raw_products` (24 columns)
- Primary key: `id` (bigint, auto-increment)
- Unique constraint: `(source, external_id)`
- Key fields: source, external_id, brand, name, description, price, currency, category, colour, sizes (jsonb), composition, original_image_urls (jsonb), raw_data (jsonb), scraped_at
- Status fields: image_status, sync_status, ximilar_status
- Default currency: `KZT` (note: scraping UAE region)

### `scraper_logs` (14 columns)
- Primary key: `id` (bigint, auto-increment)
- Key fields: scraper_name, run_id, status, records_fetched/new/updated/errors, started_at, completed_at, duration_seconds
- Indexed by: scraper_name, started_at DESC

## Environment Variables (.env)

| Variable         | Description                           |
|------------------|---------------------------------------|
| `APIFY_TOKEN`    | Apify API token (PAT)                 |
| `STAGING_DB_URL` | PostgreSQL connection string (PgBouncer) |
| `REDIS_URL`      | Redis connection string (Celery broker)  |

**NEVER stored in git.** File `.env` is in `.gitignore`.

## Apify Account

| Parameter   | Value                    |
|-------------|--------------------------|
| Username    | expensive_dream          |
| User ID     | oYVxR1sh1gQN1MByT        |
| Actor used  | datasaurus/zara (Img8lfMRf3lXNOIXl) |
| Region      | UAE (/ae/en/)            |
| Task input  | max_results=500, scrape_product_page=true |

## Git Repository

| Parameter    | Value                                        |
|--------------|----------------------------------------------|
| Remote       | http://gitlab-real.unde.life/unde/apify.git   |
| Branch       | main                                         |
| Local path   | /root/cursor/1/                              |
| Deploy path  | /opt/unde/apify/ (on clean server)           |

## Deployment on Clean Server

```bash
# 1. OS prep
hostnamectl set-hostname apify
apt update && apt upgrade -y

# 2. Install Docker (official repo)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Install node_exporter
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz \
  | tar xz -C /tmp
cp /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter
# Create systemd unit (see /etc/systemd/system/node_exporter.service)
systemctl daemon-reload && systemctl enable --now node_exporter

# 4. Clone and configure
git clone http://gitlab-real.unde.life/unde/apify.git /opt/unde/apify
cd /opt/unde/apify
cp .env.example .env
# Edit .env with real credentials

# 5. Build and run
docker compose build
docker compose up -d

# 6. Verify
docker compose ps
docker compose logs -f
curl localhost:9100/metrics | head
```

## node_exporter Systemd Unit

```ini
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Network Topology

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│  apify (89.167.110.186 / 10.1.0.9) │
│  ├── sshd :22                       │
│  ├── node_exporter :9100            │
│  ├── docker: apify-collector        │
│  └── docker: apify-beat             │
└──────────┬──────────────────────────┘
           │ internal network (10.1.0.x)
           ├──► 10.1.0.8:6432 PostgreSQL (PgBouncer)
           ├──► 10.1.0.8:5432 PostgreSQL (direct)
           └──► 10.1.0.4:6379 Redis
```
