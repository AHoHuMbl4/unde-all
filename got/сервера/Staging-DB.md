# Staging-DB — Deployment Record

## Server
- **Hostname:** staging-db
- **Provider:** Hetzner Helsinki, CPX22 (4 vCPU, 8 GB RAM)
- **OS:** Ubuntu 24.04 LTS
- **Private IP:** 10.1.0.8
- **Public IP:** 89.167.91.76

## Services

### PostgreSQL 17
- **Source:** apt.postgresql.org (v17.8)
- **Listen:** 127.0.0.1:5432 (localhost only)
- **Database:** `unde_staging`
- **Config:** `/etc/postgresql/17/main/conf.d/staging.conf`
- **Tuning:** shared_buffers=1GB, effective_cache_size=3GB, work_mem=16MB, synchronous_commit=off

### PgBouncer
- **Listen:** 10.1.0.8:6432 (private network only)
- **Mode:** transaction pooling
- **Auth:** SCRAM-SHA-256
- **Max clients:** 200, pool size: 10
- **Config:** `/etc/pgbouncer/pgbouncer.ini`
- **Userlist:** `/etc/pgbouncer/userlist.txt` (generated from pg_shadow SCRAM hashes)

### node_exporter
- **Version:** 1.8.2
- **Listen:** 0.0.0.0:9100
- **Service:** systemd (`/etc/systemd/system/node_exporter.service`)

## Database Schema

### Tables (4)

| Table | Purpose | Rows estimate |
|-------|---------|--------------|
| `raw_products` | Сырые данные товаров от скраперов | — |
| `raw_availability` | Наличие товаров по магазинам (per day) | — |
| `raw_stores` | Справочник магазинов | — |
| `scraper_logs` | Логи запусков скраперов | — |

### Users & Permissions (5)

| User | raw_products | raw_availability | raw_stores | scraper_logs |
|------|-------------|-----------------|------------|-------------|
| **apify** | SELECT, INSERT, UPDATE | — | — | SELECT, INSERT, UPDATE |
| **downloader** | SELECT, UPDATE | — | — | — |
| **ximilar** | SELECT, UPDATE | — | — | — |
| **scraper** | SELECT, INSERT, UPDATE | SELECT, INSERT, UPDATE | SELECT, INSERT, UPDATE | SELECT, INSERT, UPDATE |
| **collage** | SELECT, UPDATE | — | — | — |

### Key Indexes (16 total)
- `raw_products`: brand, image_status, sync_status, ximilar_status, external_id, scraped_at + UNIQUE(source, external_id)
- `raw_availability`: UNIQUE(brand, store_id, product_id, date), brand+store, product_id, fetched_at
- `raw_stores`: UNIQUE(brand, store_id)
- `scraper_logs`: scraper_name, started_at DESC

### Expression Index Note
`raw_availability` uses an expression unique index via immutable helper function:
```sql
CREATE FUNCTION to_date_immutable(ts TIMESTAMPTZ) RETURNS DATE AS $$
    SELECT (ts AT TIME ZONE 'UTC')::date;
$$ LANGUAGE SQL IMMUTABLE;

CREATE UNIQUE INDEX idx_raw_availability_unique_daily
    ON raw_availability(brand, store_id, product_id, to_date_immutable(fetched_at));
```

## Network Access
- pg_hba.conf allows connections from `10.1.0.0/16` for all 5 users to `unde_staging`
- Auth method: `scram-sha-256`
- Firewall managed separately (not in this repo)

## Credentials
- Auto-generated at deploy time by `deploy.sh`
- Stored on server: `/root/.staging-db-credentials` (chmod 600)
- **NEVER committed to git**

## Connection Strings
```
# Via PgBouncer (recommended):
postgresql://<user>:<pass>@10.1.0.8:6432/unde_staging

# Direct PostgreSQL (localhost only):
postgresql://<user>:<pass>@127.0.0.1:5432/unde_staging
```

## Deployment
```bash
git clone http://gitlab-real.unde.life/unde/Staging-DB.git
cd Staging-DB
sudo bash deploy.sh
```

## Deployment Log
- **2026-02-23:** Initial deployment — PG17, PgBouncer, node_exporter
  - All 4 tables created, 16 indexes, 5 users with grants
  - All tests passed (PgBouncer connections, user permissions, node_exporter)

## Fixes Applied During First Deploy
1. **SQL file permissions:** `postgres` user couldn't read files in `/root/` — added `chmod` in deploy.sh
2. **Expression UNIQUE constraint:** `UNIQUE(brand, store_id, product_id, (fetched_at::date))` not valid in PG — replaced with immutable function + expression unique index
3. **PgBouncer user:** On Ubuntu `pgbouncer` runs as `postgres`, not `pgbouncer` — deploy.sh now auto-detects
